import {
  env,
  createExecutionContext,
  waitOnExecutionContext,
} from "cloudflare:test";
import { describe, it, expect, vi, afterEach } from "vitest";
import worker from "../src/index";

const IncomingRequest = Request<unknown, IncomingRequestCfProperties>;

describe("SafeCook Search Backend - Functional Tests", () => {
  afterEach(() => {
    vi.unstubAllGlobals();
  });

  it("responds to CORS preflight requests", async () => {
    const request = new IncomingRequest(
      "https://example.com/search",
      { method: "OPTIONS" },
    );

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

    const data = await response.json() as { success: boolean };
    expect(data.success).toBe(false);
  });

  it("rejects malformed JSON", async () => {
    const request = new IncomingRequest(
      "https://example.com/search",
      {
        method: "POST",
        headers: { "Content-Type": "application/json" },
        body: "{invalid",
      },
    );

    const ctx = createExecutionContext();
    const response = await worker.fetch(request, env, ctx);
    await waitOnExecutionContext(ctx);

    expect(response.status).toBe(400);
  });

  it("rejects an empty search query", async () => {
    const request = new IncomingRequest(
      "https://example.com/search",
      {
        method: "POST",
        headers: { "Content-Type": "application/json" },
        body: JSON.stringify({ query: "   " }),
      },
    );

    const ctx = createExecutionContext();
    const response = await worker.fetch(request, env, ctx);
    await waitOnExecutionContext(ctx);

    expect(response.status).toBe(400);
  });

  it("returns an error if the API key is missing", async () => {
    const testEnv = { ...env, TAVILY_API_KEY: "" };

    const request = new IncomingRequest(
      "https://example.com/search",
      {
        method: "POST",
        headers: { "Content-Type": "application/json" },
        body: JSON.stringify({ query: "broccoli soup recipe" }),
      },
    );

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
          {
            status: 200,
            headers: { "Content-Type": "application/json" },
          },
        ),
      ),
    );

    const testEnv = { ...env, TAVILY_API_KEY: "test-key" };

    const request = new IncomingRequest(
      "https://example.com/search",
      {
        method: "POST",
        headers: { "Content-Type": "application/json" },
        body: JSON.stringify({ query: "broccoli soup recipe" }),
      },
    );

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

  it("measures response time for 10 successful mocked searches", async () => {
    
vi.stubGlobal(
  "fetch",
  vi.fn().mockImplementation(() =>
    Promise.resolve(
      new Response(
        JSON.stringify({
          answer: "Test answer",
          results: [],
        }),
        {
          status: 200,
          headers: { "Content-Type": "application/json" },
        },
      ),
    ),
  ),
);

    const testEnv = { ...env, TAVILY_API_KEY: "test-key" };
    const durations: number[] = [];
    let successfulRequests = 0;

    for (let i = 0; i < 10; i++) {
      // Create a NEW request for each iteration because request bodies
      // can only be consumed once.
      const request = new IncomingRequest(
        "https://example.com/search",
        {
          method: "POST",
          headers: { "Content-Type": "application/json" },
          body: JSON.stringify({ query: "test cooking query" }),
        },
      );

      const ctx = createExecutionContext();
      const start = performance.now();

      const response = await worker.fetch(request, testEnv, ctx);
      await waitOnExecutionContext(ctx);

      durations.push(performance.now() - start);

      expect(response.status).toBe(200);
      successfulRequests++;
    }

    const averageMs =
      durations.reduce((sum, value) => sum + value, 0) /
      durations.length;

    const sortedDurations = [...durations].sort((a, b) => a - b);
    const maxMs = sortedDurations[sortedDurations.length - 1];

    console.log(
      `[NFR] Requests: ${successfulRequests}/10 successful`,
    );
    console.log(
      `[NFR] Average mocked response time: ${averageMs.toFixed(2)} ms`,
    );
    console.log(
      `[NFR] Maximum mocked response time: ${maxMs.toFixed(2)} ms`,
    );

    // This is a local mocked-worker threshold, not a production SLA.
    expect(successfulRequests).toBe(10);
    expect(averageMs).toBeLessThan(1000);
  });

  it("handles 10 repeated invalid requests consistently", async () => {
    let correctlyRejected = 0;

    for (let i = 0; i < 10; i++) {
      const request = new IncomingRequest(
        "https://example.com/search",
        {
          method: "POST",
          headers: { "Content-Type": "application/json" },
          body: JSON.stringify({ query: "" }),
        },
      );

      const ctx = createExecutionContext();
      const response = await worker.fetch(request, env, ctx);
      await waitOnExecutionContext(ctx);

      expect(response.status).toBe(400);
      correctlyRejected++;
    }

    console.log(
      `[NFR] Invalid requests correctly rejected: ${correctlyRejected}/10`,
    );

    expect(correctlyRejected).toBe(10);
  });
});
