export default {
  async fetch(request, env) {
    const assets = env && env.ASSETS;
    if (assets && typeof assets.fetch === "function") {
      const response = await assets.fetch(request);
      if (response.status !== 404) return response;
      const url = new URL(request.url);
      if (url.pathname === "/") {
        url.pathname = "/index.html";
        return assets.fetch(new Request(url, request));
      }
      return response;
    }
    return new Response("LANTERNLINE R7 Web assets are unavailable.", {
      status: 503,
      headers: { "content-type": "text/plain; charset=utf-8" }
    });
  }
};
