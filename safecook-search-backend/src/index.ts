export interface Env {
  TAVILY_API_KEY: string;
}

export default {
  async fetch(request: Request, env: Env, ctx: ExecutionContext): Promise<Response> {
    // 1. Handle CORS preflight request
    const corsHeaders = {
      'Access-Control-Allow-Origin': '*',
      'Access-Control-Allow-Methods': 'POST, OPTIONS',
      'Access-Control-Allow-Headers': 'Content-Type',
    };

    if (request.method === 'OPTIONS') {
      return new Response(null, {
        status: 204,
        headers: corsHeaders,
      });
    }

    // 2. Routing: Only allow POST /search
    const url = new URL(request.url);
    if (request.method !== 'POST' || url.pathname !== '/search') {
      return new Response(JSON.stringify({
        success: false,
        error: 'Method Not Allowed. Use POST /search.'
      }), {
        status: 405,
        headers: {
          'Content-Type': 'application/json',
          ...corsHeaders
        }
      });
    }

    try {
      // 3. Request Validation
      let payload: any;
      try {
        payload = await request.json();
      } catch (e) {
        return new Response(JSON.stringify({
          success: false,
          error: 'Invalid JSON request payload.'
        }), {
          status: 400,
          headers: {
            'Content-Type': 'application/json',
            ...corsHeaders
          }
        });
      }

      const query = payload.query;
      if (!query || typeof query !== 'string' || query.trim() === '') {
        return new Response(JSON.stringify({
          success: false,
          error: 'Search query is required and must be a non-empty string.'
        }), {
          status: 400,
          headers: {
            'Content-Type': 'application/json',
            ...corsHeaders
          }
        });
      }

      // 4. Secret Configuration Check
      const tavilyKey = env.TAVILY_API_KEY ? env.TAVILY_API_KEY.trim() : '';
      if (tavilyKey === '') {
        console.error('TAVILY_API_KEY environment binding is missing.');
        return new Response(JSON.stringify({
          success: false,
          error: 'Tavily API key is not configured on the server.'
        }), {
          status: 500,
          headers: {
            'Content-Type': 'application/json',
            ...corsHeaders
          }
        });
      }

      // 5. Call Tavily Search API
      console.log(`Forwarding query to Tavily: "${query}"`);
      const tavilyResponse = await fetch('https://api.tavily.com/search', {
        method: 'POST',
        headers: {
          'Content-Type': 'application/json'
        },
        body: JSON.stringify({
          api_key: tavilyKey,
          query: query,
          search_depth: 'basic',
          include_answer: true
        })
      });

      console.log(`Tavily responded with status: ${tavilyResponse.status}`);

      if (!tavilyResponse.ok) {
        let errText = '';
        try {
          errText = await tavilyResponse.text();
        } catch (_) {}
        console.error(`Tavily API error: HTTP ${tavilyResponse.status} - ${errText}`);
        return new Response(JSON.stringify({
          success: false,
          error: `Tavily API error: HTTP ${tavilyResponse.status}`
        }), {
          status: tavilyResponse.status,
          headers: {
            'Content-Type': 'application/json',
            ...corsHeaders
          }
        });
      }

      // 6. Parse and format Tavily output
      const data = await tavilyResponse.json() as any;
      const results = (data.results || []).map((r: any) => ({
        title: r.title || 'Untitled',
        url: r.url || '',
        snippet: r.content || ''
      }));

      const answer = data.answer || (results.length > 0 ? results[0].snippet : '');

      return new Response(JSON.stringify({
        success: true,
        results: results,
        answer: answer
      }), {
        status: 200,
        headers: {
          'Content-Type': 'application/json',
          ...corsHeaders
        }
      });

    } catch (err: any) {
      console.error('Internal Worker Error:', err);
      return new Response(JSON.stringify({
        success: false,
        error: `Internal server error: ${err.message || err}`
      }), {
        status: 500,
        headers: {
          'Content-Type': 'application/json',
          ...corsHeaders
        }
      });
    }
  }
};
