// Prod router runs on every viewer request to the production distribution.
//
// The site is prerendered (SSG) to one HTML file per route, emitted nested:
//
//   /            -> /index.html
//   /cv          -> /cv/index.html
//   /about       -> /about/index.html
//   /assets/x.js -> /assets/x.js        (unchanged - a real file)
//
// CloudFront's S3 OAC origin does no directory-index resolution, so map clean,
// extensionless URLs to their prerendered index.html here at the edge. Requests
// for real files (anything with an extension) pass through untouched. Truly
// unknown routes miss in S3 (403) and fall back to /index.html via the
// distribution's custom_error_response, where the client router renders the 404.

function handler(event) {
  var request = event.request;
  var uri = request.uri;
  var lastSegment = uri.substring(uri.lastIndexOf("/") + 1);

  if (lastSegment === "") {
    // Directory request ("/", "/cv/") -> its index.html.
    request.uri = uri + "index.html";
  } else if (lastSegment.indexOf(".") === -1) {
    // Extensionless app route ("/cv") -> its prerendered index.html.
    request.uri = uri + "/index.html";
  }
  // else: a real asset with a file extension -> serve as-is.

  return request;
}
