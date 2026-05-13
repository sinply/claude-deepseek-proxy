const http = require("http");
const https = require("https");
const { URL } = require("url");

const upstreamBase = process.env.UPSTREAM_BASE_URL;
const listenHost = process.env.LISTEN_HOST || "127.0.0.1";
const listenPort = Number(process.env.LISTEN_PORT || 8787);

if (!upstreamBase) {
  console.error("Missing UPSTREAM_BASE_URL, for example: http://127.0.0.1:8788");
  process.exit(1);
}

const modelMap = new Map([
  ["claude-deepseek-v4-pro", "deepseek-v4-pro"],
  ["cluade-deepseek-v4-pro", "deepseek-v4-pro"],
  ["claude-deepseek-v4-flash", "deepseek-v4-flash"],
  ["cluade-deepseek-v4-flash", "deepseek-v4-flash"],
]);

function readBody(req) {
  return new Promise((resolve, reject) => {
    const chunks = [];
    req.on("data", (chunk) => chunks.push(chunk));
    req.on("end", () => resolve(Buffer.concat(chunks)));
    req.on("error", reject);
  });
}

function rewriteJsonBody(body, contentType) {
  if (!body.length || !contentType || !contentType.includes("application/json")) {
    return { body, rewritten: null };
  }

  try {
    const payload = JSON.parse(body.toString("utf8"));
    const original = payload.model;
    const mapped = modelMap.get(original);

    if (!mapped) {
      return { body, rewritten: null };
    }

    payload.model = mapped;
    return {
      body: Buffer.from(JSON.stringify(payload)),
      rewritten: `${original} -> ${mapped}`,
    };
  } catch (_error) {
    return { body, rewritten: null };
  }
}

const server = http.createServer(async (req, res) => {
  const upstreamRoot = new URL(upstreamBase.endsWith("/") ? upstreamBase : upstreamBase + "/");
  const upstreamUrl = new URL(String(req.url || "/").replace(/^\/+/, ""), upstreamRoot);
  const originalBody = await readBody(req);
  const rewritten = rewriteJsonBody(
    originalBody,
    String(req.headers["content-type"] || ""),
  );

  const headers = Object.assign({}, req.headers);
  headers.host = upstreamUrl.host;
  headers["content-length"] = Buffer.byteLength(rewritten.body);
  delete headers["accept-encoding"];

  const transport = upstreamUrl.protocol === "https:" ? https : http;
  const upstreamReq = transport.request(
    upstreamUrl,
    {
      method: req.method,
      headers,
    },
    (upstreamRes) => {
      res.writeHead(upstreamRes.statusCode || 502, upstreamRes.headers);
      upstreamRes.pipe(res);
    },
  );

  upstreamReq.on("error", (error) => {
    res.writeHead(502, { "content-type": "application/json" });
    res.end(JSON.stringify({ error: error.message }));
  });

  if (rewritten.rewritten) {
    console.error(`[model-rewrite] ${rewritten.rewritten}`);
  }

  upstreamReq.end(rewritten.body);
});

server.listen(listenPort, listenHost, () => {
  console.error(
    `Model rewrite proxy listening on http://${listenHost}:${listenPort}, upstream ${upstreamBase}`,
  );
});
