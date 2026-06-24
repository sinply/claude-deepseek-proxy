const http = require("http");
const https = require("https");
const fs = require("fs");
const path = require("path");
const { URL } = require("url");

const listenHost = process.env.LISTEN_HOST || "127.0.0.1";
const listenPort = Number(process.env.LISTEN_PORT || 8787);

const configPath =
  process.env.PROXY_CONFIG_PATH ||
  path.join(__dirname, "..", "config", "proxy-config.json");

if (!fs.existsSync(configPath)) {
  console.error("Missing proxy config: " + configPath);
  process.exit(1);
}

const config = JSON.parse(fs.readFileSync(configPath, "utf8"));
const providers = config.providers || {};

if (Object.keys(providers).length === 0) {
  console.error("No providers defined in " + configPath);
  process.exit(1);
}

function readBody(req) {
  return new Promise((resolve, reject) => {
    const chunks = [];
    req.on("data", (chunk) => chunks.push(chunk));
    req.on("end", () => resolve(Buffer.concat(chunks)));
    req.on("error", reject);
  });
}

function rewriteJsonBody(body, contentType, modelMap) {
  if (!body.length || !contentType || contentType.indexOf("application/json") === -1) {
    return { body: body, rewritten: null };
  }

  try {
    const payload = JSON.parse(body.toString("utf8"));
    const original = payload.model;
    if (!original) {
      return { body: body, rewritten: null };
    }

    const mapped = modelMap[original];
    if (!mapped) {
      return { body: body, rewritten: null };
    }

    payload.model = mapped;
    return {
      body: Buffer.from(JSON.stringify(payload)),
      rewritten: original + " -> " + mapped,
    };
  } catch (_error) {
    return { body: body, rewritten: null };
  }
}

const server = http.createServer(async (req, res) => {
  const reqUrl = String(req.url || "/");

  // /<provider>/rest/of/path -> provider + remaining path
  const match = reqUrl.match(/^\/([^/]+)(\/.*)?$/);
  if (!match) {
    res.writeHead(400, { "content-type": "application/json" });
    res.end(JSON.stringify({ error: "Invalid path, expected /<provider>/..." }));
    return;
  }

  const providerName = match[1];
  const remaining = match[2] || "/";

  const provider = providers[providerName];
  if (!provider) {
    res.writeHead(404, { "content-type": "application/json" });
    res.end(JSON.stringify({
      error: "Unknown provider: " + providerName,
      available: Object.keys(providers),
    }));
    return;
  }

  // Intercept model discovery: Claude Code requires /v1/models to return official
  // Claude model IDs. Upstream third-party endpoints often 404 or return non-Claude
  // names, so synthesize an Anthropic-format response from the provider's map keys.
  const pathOnly = remaining.split("?")[0];
  if (req.method === "GET" && pathOnly === "/v1/models") {
    const modelIds = Object.keys(provider.map || {});
    const data = modelIds.map(function (id) {
      return {
        id: id,
        display_name: id,
        created_at: "2025-01-01T00:00:00Z",
        type: "model",
      };
    });
    const payload = {
      data: data,
      has_more: false,
      first_id: modelIds[0] || null,
      last_id: modelIds[modelIds.length - 1] || null,
    };
    const body = Buffer.from(JSON.stringify(payload));
    res.writeHead(200, {
      "content-type": "application/json",
      "content-length": body.length,
    });
    res.end(body);
    console.error("[" + providerName + "] GET /v1/models -> synthetic (" + modelIds.length + " models)");
    return;
  }

  const upstreamRoot = new URL(
    provider.upstream.endsWith("/") ? provider.upstream : provider.upstream + "/",
  );
  const upstreamUrl = new URL(remaining.replace(/^\/+/, ""), upstreamRoot);

  const originalBody = await readBody(req);
  const rewritten = rewriteJsonBody(
    originalBody,
    String(req.headers["content-type"] || ""),
    provider.map || {},
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
      headers: headers,
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
    console.error("[" + providerName + "] " + rewritten.rewritten);
  } else {
    console.error("[" + providerName + "] " + req.method + " " + remaining + " (no model rewrite)");
  }

  upstreamReq.end(rewritten.body);
});

server.listen(listenPort, listenHost, () => {
  console.error(
    "Model rewrite proxy listening on http://" + listenHost + ":" + listenPort,
  );
  console.error("Providers:");
  Object.keys(providers).forEach(function (name) {
    console.error("  /" + name + "/ -> " + providers[name].upstream);
  });
});
