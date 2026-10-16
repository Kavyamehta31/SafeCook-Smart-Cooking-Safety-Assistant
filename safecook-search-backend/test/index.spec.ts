import {
  env,
  createExecutionContext,
  waitOnExecutionContext,
  SELF,
} from "cloudflare:test";
import { describe, it, expect, vi, afterEach } from "vitest";
import worker from "../src/index";

const IncomingRequest = Request<unknown, IncomingRequestCfProperties>;

describe("SafeCook Search Backend - Functional Tests", () => {
  afterEach(() => {
    vi.unstubAllGlobals();
  });

  it("responds to CORS preflight requests", async () => {
    const request = new IncomingRequest("https://example.com/search", {
      method: "OPTIONS",
    });
    const ctx = createExecutionContext();
    const response = await worker.fetch(request, env, ctx);
    await waitOnExecutionContext(ctx);

    expect(response.status).toBe(204);
    expect(response.headers.get("Access-Control-Allow-Origin")).toBe("*");
  });

  it("rejects unsupported routes and methods", async () => {
    const request = new IncomingRequest("https://example.com/");
    const ctx = createExecutionContext();
    const response = await worker.fetch(request, env, ctx);
    await waitOnExecutionContext(ctx);

    expect(response.status).toBe(405);
    expect((await response.json() as { success: boolean }).success).toBe(false);
  });

  it("rejects malformed JSON", async () => {
    const request = new IncomingRequest("https://example.com/search", {
      method: "POST",
      headers: { "Content-Type": "application/json" },
      body: "{invalid",
    });
    const ctx = createExecutionContext();
    const response = await worker.fetch(request, env, ctx);
    await waitOnExecutionContext(ctx);

    expect(response.status).toBe(400);
  });

  it("rejects an empty search query", async () => {
    const request = new IncomingRequest("https://example.com/search", {
      method: "POST",
      headers: { "Content-Type": "application/json" },
      body: JSON.stringify({ query: "   " }),
    });
    const ctx = createExecutionContext();
    const response = await worker.fetch(request, env, ctx);
    await waitOnExecutionContext(ctx);

    expect(response.status).toBe(400);
  });

  it("returns an error if the API key is missing", async () => {
    const testEnv = { ...env, TAVILY_API_KEY: "" };
    const request = new IncomingRequest("https://example.com/search", {
      method: "POST",
      headers: { "Content-Type": "application/json" },
      body: JSON.stringify({ query: "broccoli soup recipe" }),
    });
    const ctx = createExecutionContext();
    const response = await worker.fetch(request, testEnv, ctx);
    await waitOnExecutionContext(ctx);

    expect(response.status).toBe(500);
  });

  it("returns search results when Tavily succeeds", async () => {
    vi.stubGlobal(
      "fetch",
      vi.fn().mockResolvedValue(
        new Response(
          JSON.stringify({
            answer: "Example cooking answer",
            results: [
              {
                title: "Soup Recipe",
                url: "https://example.com/soup",
                content: "Example soup instructions",
              },
            ],
          }),
          { status: 200, headers: { "Content-Type": "application/json" } },
        ),
      ),
    );

    const testEnv = { ...env, TAVILY_API_KEY: "test-key" };
    const request = new IncomingRequest("https://example.com/search", {
      method: "POST",
      headers: { "Content-Type": "application/json" },
      body: JSON.stringify({ query: "broccoli soup recipe" }),
    });
    const ctx = createExecutionContext();
    const response = await worker.fetch(request, testEnv, ctx);
    await waitOnExecutionContext(ctx);

    expect(response.status).toBe(200);
    const data = await response.json() as {
      success: boolean;
      answer: string;
      results: unknown[];
    };
    expect(data.success).toBe(true);
    expect(data.answer).toBe("Example cooking answer");
    expect(data.results).toHaveLength(1);
  });
});

describe("SafeCook Search Backend - Non-Functional Checks", () => {
  afterEach(() => {
    vi.unstubAllGlobals();
  });

  it("measures response time for a successful mocked search", async () => {
    vi.stubGlobal(
      "fetch",
      vi.fn().mockResolvedValue(
        new Response(
          JSON.stringify({ answer: "Test answer", results: [] }),
          { status: 200, headers: { "Content-Type": "application/json" } },
        ),
      ),
    );

    const testEnv = { ...env, TAVILY_API_KEY: "test-key" };
    const request = new IncomingRequest("https://example.com/search", {
      method: "POST",
      headers: { "Content-Type": "application/json" },
      body: JSON.stringify({ query: "test cooking query" }),
    });

    const durations: number[] = [];

    for (let i = 0; i < 10; i++) {
      const ctx = createExecutionContext();
      const start = performance.now();
      const response = await worker.fetch(request.clone(), testEnv, ctx);
      await waitOnExecutionContext(ctx);
      durations.push(performance.now() - start);
      expect(response.status).toBe(200);
    }

    const averageMs =
      durations.reduce((sum, value) => sum + value, 0) / durations.length;

    console.log(
      `[NFR] Mocked search requests: ${durations.length}; average response time: ${averageMs.toFixed(2)} ms`,
    );

    // A generous threshold for local worker execution, not a production SLA.
    expect(averageMs).toBeLessThan(1000);
  });

  it("handles repeated invalid requests consistently", async () => {
    for (let i = 0; i < 10; i++) {
      const request = new IncomingRequest("https://example.com/search", {
        method: "POST",
        headers: { "Content-Type": "application/json" },
        body: JSON.stringify({ query: "" }),
      });

      const ctx = createExecutionContext();
      const response = await worker.fetch(request, env, ctx);
      await waitOnExecutionContext(ctx);

      expect(response.status).toBe(400);
    }
  });
});
