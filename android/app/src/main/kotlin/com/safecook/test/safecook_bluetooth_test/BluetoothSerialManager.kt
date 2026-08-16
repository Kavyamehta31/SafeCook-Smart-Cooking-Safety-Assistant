package com.safecook.test.safecook_bluetooth_test

import android.bluetooth.BluetoothAdapter
import android.bluetooth.BluetoothDevice
import android.bluetooth.BluetoothGatt
import android.bluetooth.BluetoothGattCallback
import android.bluetooth.BluetoothGattCharacteristic
import android.bluetooth.BluetoothGattDescriptor
import android.bluetooth.BluetoothProfile
import android.content.Context
import android.os.Build
import android.os.Handler
import android.os.Looper
import android.util.Log
import io.flutter.plugin.common.EventChannel.EventSink
import io.flutter.plugin.common.MethodCall
import io.flutter.plugin.common.MethodChannel.Result
import java.util.UUID
import java.util.concurrent.ConcurrentLinkedQueue

/**
 * SafeCook BLE GATT Manager.
 *
 * ══════════════════════════════════════════════════════════════════
 * ROOT CAUSE SUMMARY
 * ══════════════════════════════════════════════════════════════════
 *
 * The physical module (name=HC-05, MAC=FA:B8:03:6B:1F:57) reports:
 *   BluetoothDevice.type = 2  (DEVICE_TYPE_LE — Bluetooth Low Energy)
 *
 * All Classic RFCOMM/SPP approaches failed because this module is NOT
 * a Classic Bluetooth device. It is an HC-05 V2.3 LE, a BLE-only module
 * that mimics the HC-05 brand but operates entirely over BLE GATT.
 *
 * UART SERVICE:
 *   Service UUID:        0000FFE0-0000-1000-8000-00805F9B34FB
 *   Characteristic UUID: 0000FFE1-0000-1000-8000-00805F9B34FB
 *   Properties:          NOTIFY + WRITE (no response)
 *   Function:            Serial UART bridge (HM-10 / CC2541 family)
 *
 * Data received on Arduino TX → HC-05 LE RX pin → FFE1 BLE notifications
 * → onCharacteristicChanged → EventChannel → Flutter → GAS/DIST parser
 *
 * GATT connection uses TRANSPORT_LE explicitly to force BLE transport
 * on dual-mode Android adapters.
 *
 * ══════════════════════════════════════════════════════════════════
 * DISCOVERY STRATEGY (ordered by priority)
 * ══════════════════════════════════════════════════════════════════
 *
 * Tier 1: FFE0/FFE1  — HC-05 LE, HM-10, CC2541 UART bridge modules
 * Tier 2: NUS        — Nordic UART Service (6E400001/6E400003)
 * Tier 3: All notify — Subscribe to ALL notify/indicate characteristics
 *
 * Dynamic discovery is always performed first regardless of tier.
 * All services, characteristics, and properties are logged at connect time.
 * ══════════════════════════════════════════════════════════════════
 */
class BluetoothSerialManager(private val context: Context) {

    companion object {
        private const val TAG = "SafeCookBLE"

        // Client Characteristic Configuration Descriptor (enables notifications/indications)
        private val CCCD_UUID = UUID.fromString("00002902-0000-1000-8000-00805f9b34fb")

        // Tier 1: FFE0/FFE1 — HC-05 V2.3 LE, HM-10, CC2541-based BLE UART modules
        private val FFE0_SERVICE  = UUID.fromString("0000ffe0-0000-1000-8000-00805f9b34fb")
        private val FFE1_CHAR     = UUID.fromString("0000ffe1-0000-1000-8000-00805f9b34fb")

        // Tier 2: Nordic UART Service
        private val NUS_SERVICE   = UUID.fromString("6e400001-b5a3-f393-e0a9-e50e24dcca9e")
        private val NUS_TX_CHAR   = UUID.fromString("6e400003-b5a3-f393-e0a9-e50e24dcca9e") // notify
    }

    private val bluetoothAdapter: BluetoothAdapter? = BluetoothAdapter.getDefaultAdapter()
    private val mainHandler = Handler(Looper.getMainLooper())

    private var bluetoothGatt: BluetoothGatt? = null
    private var eventSink: EventSink? = null

    // Queued CCCD descriptor writes — BLE requires sequential writes; each must complete
    // before the next one starts (enforced via onDescriptorWrite callback).
    private val descriptorWriteQueue = ConcurrentLinkedQueue<BluetoothGattDescriptor>()

    @Volatile private var pendingDescriptorWrite = false
    @Volatile private var isConnecting = false
    @Volatile private var isConnected = false

    // ─────────────────────────────────────────────────────────────────────────
    // GATT Callback — all GATT results arrive here on a Binder thread
    // ─────────────────────────────────────────────────────────────────────────

    private val gattCallback = object : BluetoothGattCallback() {

        override fun onConnectionStateChange(gatt: BluetoothGatt, status: Int, newState: Int) {
            Log.d(TAG, "[SafeCook BLE] onConnectionStateChange: newState=$newState status=$status")

            when (newState) {
                BluetoothProfile.STATE_CONNECTED -> {
                    Log.d(TAG, "[SafeCook BLE] GATT connected")
                    Log.d(TAG, "[SafeCook BLE] Device name=${gatt.device.name}")
                    Log.d(TAG, "[SafeCook BLE] Address=${gatt.device.address}")
                    isConnected = true
                    isConnecting = false
                    sendEvent("status", "connected")

                    // Request larger MTU to improve UART throughput.
                    // onMtuChanged → discoverServices() to ensure correct ordering.
                    Log.d(TAG, "[SafeCook BLE] Requesting MTU 512...")
                    gatt.requestMtu(512)
                }

                BluetoothProfile.STATE_DISCONNECTED -> {
                    Log.d(TAG, "[SafeCook BLE] GATT disconnected (status=$status)")
                    isConnected = false
                    isConnecting = false
                    pendingDescriptorWrite = false
                    descriptorWriteQueue.clear()

                    // Close GATT resources — critical to prevent handle leaks on Android
                    gatt.close()
                    bluetoothGatt = null

                    if (status != BluetoothGatt.GATT_SUCCESS) {
                        sendEvent("error", "GATT disconnected with status $status")
                    }
                    sendEvent("status", "disconnected")
                }
            }
        }

        override fun onMtuChanged(gatt: BluetoothGatt, mtu: Int, status: Int) {
            Log.d(TAG, "[SafeCook BLE] MTU=${mtu} status=$status")
            // Start service discovery after MTU is settled
            Log.d(TAG, "[SafeCook BLE] Starting service discovery...")
            gatt.discoverServices()
        }

        override fun onServicesDiscovered(gatt: BluetoothGatt, status: Int) {
            if (status != BluetoothGatt.GATT_SUCCESS) {
                Log.e(TAG, "[SafeCook BLE] Service discovery FAILED: status=$status")
                sendEvent("error", "Service discovery failed: $status")
                return
            }

            Log.d(TAG, "[SafeCook BLE] ━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━")
            Log.d(TAG, "[SafeCook BLE] GATT Services Discovered")
            sendEvent("status", "services_discovered")

            val services = gatt.services
            Log.d(TAG, "[SafeCook BLE] Total services: ${services.size}")

            val allNotifyChars = mutableListOf<BluetoothGattCharacteristic>()

            for (service in services) {
                Log.d(TAG, "[SafeCook BLE]")
                Log.d(TAG, "[SafeCook BLE] SERVICE uuid=${service.uuid}")

                for (char in service.characteristics) {
                    val props = char.properties
                    val propsStr = buildPropertiesString(props)
                    Log.d(TAG, "[SafeCook BLE]   CHAR uuid=${char.uuid}")
                    Log.d(TAG, "[SafeCook BLE]   properties=$propsStr (raw=$props)")

                    val canNotify = (props and BluetoothGattCharacteristic.PROPERTY_NOTIFY != 0) ||
                                   (props and BluetoothGattCharacteristic.PROPERTY_INDICATE != 0)
                    if (canNotify) {
                        allNotifyChars.add(char)
                        Log.d(TAG, "[SafeCook BLE]   ↳ NOTIFY candidate")
                    }
                }
            }

            Log.d(TAG, "[SafeCook BLE] ━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━")
            subscribeToUartNotifications(gatt, allNotifyChars)
        }

        override fun onDescriptorWrite(
            gatt: BluetoothGatt,
            descriptor: BluetoothGattDescriptor,
            status: Int
        ) {
            val charUuid = descriptor.characteristic.uuid
            if (status == BluetoothGatt.GATT_SUCCESS) {
                Log.d(TAG, "[SafeCook BLE] ✓ Notification ENABLED on $charUuid")
                sendEvent("status", "notifications_enabled")
            } else {
                Log.w(TAG, "[SafeCook BLE] ✗ Descriptor write FAILED for $charUuid (status=$status)")
            }
            // Write completed — process next queued descriptor
            pendingDescriptorWrite = false
            processNextDescriptorWrite(gatt)
        }

        /**
         * onCharacteristicChanged — called when a notify/indicate characteristic delivers new data.
         * Dual override: deprecated pre-API-33 version + new API-33 version.
         * Android calls the appropriate one based on the running OS version.
         */
        @Suppress("DEPRECATION")
        override fun onCharacteristicChanged(
            gatt: BluetoothGatt,
            characteristic: BluetoothGattCharacteristic
        ) {
            if (Build.VERSION.SDK_INT < Build.VERSION_CODES.TIRAMISU) {
                val data = characteristic.value
                if (data != null && data.isNotEmpty()) {
                    Log.d(TAG, "[SafeCook BLE] RX ${data.size} bytes on ${characteristic.uuid}")
                    sendEvent("read", data)
                }
            }
        }

        override fun onCharacteristicChanged(
            gatt: BluetoothGatt,
            characteristic: BluetoothGattCharacteristic,
            value: ByteArray
        ) {
            if (value.isNotEmpty()) {
                Log.d(TAG, "[SafeCook BLE] RX ${value.size} bytes on ${characteristic.uuid}")
                sendEvent("read", value)
            }
        }
    }

    // ─────────────────────────────────────────────────────────────────────────
    // Notification subscription strategy
    // ─────────────────────────────────────────────────────────────────────────

    private fun subscribeToUartNotifications(
        gatt: BluetoothGatt,
        allNotifyChars: List<BluetoothGattCharacteristic>
    ) {
        // Tier 1: FFE0 service / FFE1 characteristic — HC-05 V2.3 LE, HM-10 (CC2541)
        val ffe1 = gatt.getService(FFE0_SERVICE)?.getCharacteristic(FFE1_CHAR)
        if (ffe1 != null) {
            Log.d(TAG, "[SafeCook BLE] ✓ Found FFE0/FFE1 UART service (HC-05 LE / HM-10)")
            Log.d(TAG, "[SafeCook BLE]   Subscribing to FFE1 notifications...")
            queueNotificationEnable(gatt, ffe1)
            return
        }

        // Tier 2: Nordic UART Service TX characteristic
        val nusTx = gatt.getService(NUS_SERVICE)?.getCharacteristic(NUS_TX_CHAR)
        if (nusTx != null) {
            Log.d(TAG, "[SafeCook BLE] ✓ Found Nordic UART Service (NUS)")
            Log.d(TAG, "[SafeCook BLE]   Subscribing to NUS TX notifications...")
            queueNotificationEnable(gatt, nusTx)
            return
        }

        // Tier 3: Subscribe to all discovered notify/indicate characteristics
        if (allNotifyChars.isNotEmpty()) {
            Log.d(TAG, "[SafeCook BLE] No known UART service found; subscribing to ALL " +
                       "${allNotifyChars.size} notify characteristic(s)")
            for (char in allNotifyChars) {
                queueNotificationEnable(gatt, char)
            }
            return
        }

        Log.w(TAG, "[SafeCook BLE] ✗ No notify characteristics found on device")
        sendEvent("error", "No notify characteristics found — device may not support BLE UART")
    }

    private fun queueNotificationEnable(gatt: BluetoothGatt, char: BluetoothGattCharacteristic) {
        val cccd = char.getDescriptor(CCCD_UUID)
        if (cccd == null) {
            // Some modules omit the CCCD descriptor but still send notifications
            // once setCharacteristicNotification is called — try without descriptor write.
            Log.w(TAG, "[SafeCook BLE] No CCCD descriptor on ${char.uuid} — enabling notification without descriptor write")
            gatt.setCharacteristicNotification(char, true)
            sendEvent("status", "notifications_enabled")
            return
        }
        descriptorWriteQueue.add(cccd)
        if (!pendingDescriptorWrite) {
            processNextDescriptorWrite(gatt)
        }
    }

    private fun processNextDescriptorWrite(gatt: BluetoothGatt) {
        val descriptor = descriptorWriteQueue.poll() ?: return
        val char = descriptor.characteristic

        gatt.setCharacteristicNotification(char, true)

        // Choose notification vs indication based on characteristic properties
        val enableValue = if (char.properties and BluetoothGattCharacteristic.PROPERTY_INDICATE != 0)
            BluetoothGattDescriptor.ENABLE_INDICATION_VALUE
        else
            BluetoothGattDescriptor.ENABLE_NOTIFICATION_VALUE

        pendingDescriptorWrite = true
        Log.d(TAG, "[SafeCook BLE] Writing CCCD for ${char.uuid} value=${enableValue.contentToString()}")

        if (Build.VERSION.SDK_INT >= Build.VERSION_CODES.TIRAMISU) {
            // API 33+ new non-deprecated API
            gatt.writeDescriptor(descriptor, enableValue)
        } else {
            // Pre-API 33
            @Suppress("DEPRECATION")
            descriptor.value = enableValue
            @Suppress("DEPRECATION")
            gatt.writeDescriptor(descriptor)
        }
    }

    // ─────────────────────────────────────────────────────────────────────────
    // Public interface — same signatures as old RFCOMM manager for compatibility
    // ─────────────────────────────────────────────────────────────────────────

    fun setEventSink(sink: EventSink?) {
        eventSink = sink
    }

    fun handleMethodCall(call: MethodCall, result: Result) {
        when (call.method) {
            "getBluetoothState" -> {
                result.success(bluetoothAdapter?.isEnabled ?: false)
            }
            "getBondedDevices" -> {
                getBondedDevices(result)
            }
            "connect" -> {
                val address = call.argument<String>("address")
                if (address == null) {
                    result.error("invalidAddress", "MAC Address is required", null)
                    return
                }
                connectBle(address, result)
            }
            "disconnect" -> {
                disconnectGatt()
                result.success(null)
            }
            else -> result.notImplemented()
        }
    }

    // ─────────────────────────────────────────────────────────────────────────
    // Device listing — returns ALL bonded devices, no type filtering
    // ─────────────────────────────────────────────────────────────────────────

    private fun getBondedDevices(result: Result) {
        val devicesList = mutableListOf<Map<String, String>>()
        if (bluetoothAdapter != null && bluetoothAdapter.isEnabled) {
            try {
                val bondedDevices = bluetoothAdapter.bondedDevices
                Log.d(TAG, "[SafeCook BT DEBUG] bondedDevices count = ${bondedDevices.size}")

                for (device in bondedDevices) {
                    Log.d(TAG, "[SafeCook BT DEBUG] device name=${device.name}")
                    Log.d(TAG, "[SafeCook BT DEBUG] device address=${device.address}")
                    Log.d(TAG, "[SafeCook BT DEBUG] device type=${device.type}") // 0=UNKNOWN,1=CLASSIC,2=LE,3=DUAL
                    Log.d(TAG, "[SafeCook BT DEBUG] bond state=${device.bondState}")  // 12=BONDED
                    // NO type filter — return ALL bonded devices unconditionally
                    devicesList.add(
                        mapOf(
                            "name"      to (device.name ?: "Unknown Device"),
                            "address"   to device.address,
                            "bondState" to "bonded",
                            "type"      to device.type.toString()
                        )
                    )
                }
            } catch (e: SecurityException) {
                Log.e(TAG, "[SafeCook BT DEBUG] SecurityException: ${e.message}")
            }
        }
        result.success(devicesList)
    }

    // ─────────────────────────────────────────────────────────────────────────
    // BLE GATT connection
    // ─────────────────────────────────────────────────────────────────────────

    @Synchronized
    private fun connectBle(address: String, result: Result) {
        if (isConnecting || isConnected) {
            result.error("alreadyConnecting", "Already connecting or connected", null)
            return
        }
        val adapter = bluetoothAdapter
        if (adapter == null || !adapter.isEnabled) {
            result.error("bluetoothDisabled", "Bluetooth adapter not available or disabled", null)
            return
        }

        isConnecting = true
        pendingDescriptorWrite = false
        descriptorWriteQueue.clear()

        Log.d(TAG, "[SafeCook BLE] ━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━")
        Log.d(TAG, "[SafeCook BLE] Initiating BLE GATT connection")
        Log.d(TAG, "[SafeCook BLE] Target address: $address")
        sendEvent("status", "connecting")

        try {
            val device = adapter.getRemoteDevice(address)
            Log.d(TAG, "[SafeCook BLE] Device name=${device.name}")
            Log.d(TAG, "[SafeCook BLE] Device type=${device.type} (2=LE expected)")

            // connectGatt with TRANSPORT_LE — forces BLE transport.
            // autoConnect=false for faster initial connection (true causes background scan retry).
            bluetoothGatt = if (Build.VERSION.SDK_INT >= Build.VERSION_CODES.M) {
                device.connectGatt(context, false, gattCallback, BluetoothDevice.TRANSPORT_LE)
            } else {
                device.connectGatt(context, false, gattCallback)
            }

            Log.d(TAG, "[SafeCook BLE] connectGatt() called — waiting for onConnectionStateChange...")

            // Result returned immediately; actual connection progress via EventChannel status events
            mainHandler.post {
                try { result.success(true) } catch (ignored: Exception) {}
            }
        } catch (e: Exception) {
            isConnecting = false
            Log.e(TAG, "[SafeCook BLE] connectGatt() threw: ${e.message}")
            mainHandler.post {
                try { result.error("connectionFailed", e.message, null) } catch (ignored: Exception) {}
            }
            sendEvent("error", e.message ?: "GATT connection initiation failed")
            sendEvent("status", "disconnected")
        }
    }

    fun disconnectGatt() {
        isConnected = false
        isConnecting = false
        pendingDescriptorWrite = false
        descriptorWriteQueue.clear()
        Log.d(TAG, "[SafeCook BLE] Disconnect requested")
        try {
            bluetoothGatt?.disconnect()
            // gatt.close() is called in onConnectionStateChange(DISCONNECTED)
        } catch (e: Exception) {
            Log.e(TAG, "[SafeCook BLE] disconnect() threw: ${e.message}")
            // Force cleanup if disconnect() itself fails
            try { bluetoothGatt?.close() } catch (ignored: Exception) {}
            bluetoothGatt = null
            sendEvent("status", "disconnected")
        }
    }

    fun destroy() {
        isConnected = false
        isConnecting = false
        try { bluetoothGatt?.disconnect() } catch (ignored: Exception) {}
        try { bluetoothGatt?.close() } catch (ignored: Exception) {}
        bluetoothGatt = null
    }

    // ─────────────────────────────────────────────────────────────────────────
    // Utilities
    // ─────────────────────────────────────────────────────────────────────────

    private fun buildPropertiesString(props: Int): String {
        return buildString {
            if (props and BluetoothGattCharacteristic.PROPERTY_READ             != 0) append("READ ")
            if (props and BluetoothGattCharacteristic.PROPERTY_WRITE            != 0) append("WRITE ")
            if (props and BluetoothGattCharacteristic.PROPERTY_WRITE_NO_RESPONSE!= 0) append("WRITE_NO_RSP ")
            if (props and BluetoothGattCharacteristic.PROPERTY_NOTIFY           != 0) append("NOTIFY ")
            if (props and BluetoothGattCharacteristic.PROPERTY_INDICATE         != 0) append("INDICATE ")
        }.trim().ifEmpty { "NONE" }
    }

    private fun sendEvent(event: String, value: Any) {
        val sink = eventSink ?: return
        mainHandler.post {
            try {
                sink.success(mapOf("event" to event, "value" to value))
            } catch (ignored: Exception) {}
        }
    }
}
