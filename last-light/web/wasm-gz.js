// Cloudflare Pages only accepts files up to 25 MiB, but Godot's engine (index.wasm) is about 42 MiB.
// CI uploads it gzipped as index.wasm.gz (about 9 MiB). This shim runs before the engine starts:
// when Godot asks for a .wasm file, it downloads the .gz version and unpacks it in the browser.
(function () {
  if (typeof DecompressionStream === "undefined") return; // very old browser: fall back to index.wasm
  const realFetch = window.fetch.bind(window);
  const isWasm = /\.wasm(\?.*)?$/;

  window.fetch = async function (input, init) {
    const url = typeof input === "string" ? input : input instanceof URL ? input.href : input.url;
    if (!isWasm.test(url)) return realFetch(input, init);

    const res = await realFetch(url.replace(/\.wasm(\?.*)?$/, ".wasm.gz$1"), init);
    if (!res.ok) return realFetch(input, init);
    let bytes = new Uint8Array(await res.arrayBuffer());
    // The server may already have decompressed it for us; only unpack real gzip data.
    if (bytes[0] === 0x1f && bytes[1] === 0x8b) {
      const stream = new Blob([bytes]).stream().pipeThrough(new DecompressionStream("gzip"));
      bytes = new Uint8Array(await new Response(stream).arrayBuffer());
    }
    return new Response(bytes, { status: 200, headers: { "Content-Type": "application/wasm" } });
  };
})();
