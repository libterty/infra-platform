// Client-side routes such as /orders/42 have no file in the bucket. Rewrite any path whose last segment has no
// file extension to /index.html so the SPA can route it; requests for files (app.js, logo.png) pass through.
function handler(event) {
  var request = event.request;
  var last = request.uri.substring(request.uri.lastIndexOf('/') + 1);
  if (last.indexOf('.') === -1) {
    request.uri = '/index.html';
  }
  return request;
}
