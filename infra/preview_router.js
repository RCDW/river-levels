// Preview router runs on every viewer request to the preview distribution.
//
// Maps a per-PR subdomain to a per-PR key prefix in the shared preview bucket,
// and provides SPA fallback scoped to that PR:
//
//   pr-7.preview.reecewall.dev/                  -> /pr-7/index.html
//   pr-7.preview.reecewall.dev/assets/app.123.js -> /pr-7/assets/app.123.js
//   pr-7.preview.reecewall.dev/some/route        -> /pr-7/index.html  (client routing)
//
// Because the prefix is applied here at the edge, the app is built with the
// default Vite base ("/") no per-PR build config needed.

function handler(event) {
  var request = event.request;
  var host = request.headers.host.value;
  var label = host.split(".")[0]; // "pr-7" from "pr-7.preview.reecewall.dev"

  // Defensive: only pr-<number> hosts are valid. Anything else (including a
  // direct hit on preview.reecewall.dev) gets a flat 404 rather than being
  // mapped to an arbitrary bucket prefix.
  if (!/^pr-\d+$/.test(label)) {
    return { statusCode: 404, statusDescription: "Not Found" };
  }

  var uri = request.uri;
  var lastSegment = uri.substring(uri.lastIndexOf("/") + 1);

  // No file extension in the last segment (or bare "/") => an app route.
  // Serve this PR's index.html and let React Router take over client-side.
  if (lastSegment === "" || lastSegment.indexOf(".") === -1) {
    request.uri = "/" + label + "/index.html";
  } else {
    request.uri = "/" + label + uri;
  }

  return request;
}
