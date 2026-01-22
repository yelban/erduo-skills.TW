/**
 * Azure TTS Cloudflare Worker Proxy
 *
 * 部署步驟：
 * 1. 登入 Cloudflare Dashboard
 * 2. 進入 Workers & Pages
 * 3. 建立新 Worker
 * 4. 貼上此代碼
 * 5. 在 Settings > Variables 設定環境變數：
 *    - AZURE_KEY: 你的 Azure Speech API Key
 *    - AZURE_REGION: 區域（如 japanwest）
 * 6. 部署並取得 Worker URL
 */

export default {
  async fetch(request, env) {
    // 從環境變數取得設定（安全，不會暴露在代碼中）
    const AZURE_KEY = env.AZURE_KEY;
    const AZURE_REGION = env.AZURE_REGION || 'japanwest';

    // CORS 預檢請求
    if (request.method === 'OPTIONS') {
      return new Response(null, {
        headers: {
          'Access-Control-Allow-Origin': '*',
          'Access-Control-Allow-Methods': 'POST, OPTIONS',
          'Access-Control-Allow-Headers': 'Content-Type',
          'Access-Control-Max-Age': '86400',
        }
      });
    }

    // 只允許 POST 請求
    if (request.method !== 'POST') {
      return new Response('Method not allowed', { status: 405 });
    }

    // 檢查環境變數
    if (!AZURE_KEY) {
      return new Response(JSON.stringify({ error: 'Azure API Key not configured' }), {
        status: 500,
        headers: {
          'Content-Type': 'application/json',
          'Access-Control-Allow-Origin': '*',
        }
      });
    }

    try {
      // 取得請求內容（SSML）
      const ssml = await request.text();

      // 轉發請求到 Azure TTS API
      const azureEndpoint = `https://${AZURE_REGION}.tts.speech.microsoft.com/cognitiveservices/v1`;

      const response = await fetch(azureEndpoint, {
        method: 'POST',
        headers: {
          'Ocp-Apim-Subscription-Key': AZURE_KEY,
          'Content-Type': 'application/ssml+xml',
          'X-Microsoft-OutputFormat': 'audio-16khz-128kbitrate-mono-mp3',
          'User-Agent': 'DailyPicksAINews/1.0',
        },
        body: ssml,
      });

      if (!response.ok) {
        const errorText = await response.text();
        return new Response(JSON.stringify({
          error: `Azure TTS error: ${response.status}`,
          details: errorText
        }), {
          status: response.status,
          headers: {
            'Content-Type': 'application/json',
            'Access-Control-Allow-Origin': '*',
          }
        });
      }

      // 回傳音訊資料
      const audioData = await response.arrayBuffer();
      return new Response(audioData, {
        headers: {
          'Content-Type': 'audio/mpeg',
          'Access-Control-Allow-Origin': '*',
          'Cache-Control': 'no-cache',
        }
      });

    } catch (error) {
      return new Response(JSON.stringify({ error: error.message }), {
        status: 500,
        headers: {
          'Content-Type': 'application/json',
          'Access-Control-Allow-Origin': '*',
        }
      });
    }
  }
};
