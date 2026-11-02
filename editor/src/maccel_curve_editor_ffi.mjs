export function toggle_fullscreen() {
  if (document.fullscreenElement) {
    document.exitFullscreen();
  } else {
    document.documentElement.requestFullscreen();
  }
}

// Subscribe to the server-sent speed stream. Samples arrive ~100 times a
// second; they are coalesced to one dispatch per animation frame so the
// marker is always current without rendering faster than the screen.
export function listen_speeds(url, callback) {
  const source = new EventSource(url);
  let latest = null;
  let scheduled = false;
  source.onmessage = (event) => {
    latest = parseFloat(event.data);
    if (!scheduled) {
      scheduled = true;
      requestAnimationFrame(() => {
        scheduled = false;
        if (latest !== null && !Number.isNaN(latest)) callback(latest);
      });
    }
  };
}
