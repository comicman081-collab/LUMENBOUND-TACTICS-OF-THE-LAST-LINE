/* Browser decoding follows the media clock, independently of WASM frame rate. */
(() => {
  if (window.__lumenIntro) return;
  const api = window.__lumenIntro = {done: false, time: 0, duration: 50, error: '', root: null};
  api.stop = () => {
    if (api.video) { api.video.pause(); api.video.removeAttribute('src'); api.video.load(); }
    api.root?.remove(); api.root = null; api.video = null;
  };
  api.start = (src, volume) => {
    api.stop(); api.done = false; api.time = 0; api.error = '';
    const root = document.createElement('div'); api.root = root;
    Object.assign(root.style, {position:'fixed', inset:'0', background:'#000', zIndex:'2147483000'});
    const video = document.createElement('video'); api.video = video;
    video.src = src; video.playsInline = true; video.preload = 'auto'; video.volume = Math.max(0, Math.min(1, volume));
    video.muted = volume <= 0;
    Object.assign(video.style, {width:'100%', height:'100%', objectFit:'contain'});
    const button = (text, style, action) => {
      const b = document.createElement('button'); b.textContent = text;
      Object.assign(b.style, {position:'absolute', color:'#f1f6fb', background:'#102635e8', border:'1px solid #80b7bc', borderRadius:'4px', padding:'12px 24px', font:'16px sans-serif', cursor:'pointer'}, style);
      b.onclick = action; root.append(b); return b;
    };
    root.append(video);
    button('건너뛰기 ›', {right:'24px', top:'24px'}, () => {api.done = true; api.stop();});
    const retry = button('영상 재생', {left:'50%', top:'50%', transform:'translate(-50%,-50%)', display:'none'}, () => {
      video.play().then(() => {retry.style.display = 'none'; api.error = '';}).catch(() => {});
    });
    video.addEventListener('timeupdate', () => {if (!api.done && api.video === video) api.time = video.currentTime;});
    video.addEventListener('loadedmetadata', () => {api.duration = video.duration;});
    video.addEventListener('ended', () => {api.time = video.currentTime; api.done = true; api.stop();});
    video.addEventListener('error', () => {if (api.video !== video || api.done) return; api.error = '영상을 불러오지 못했습니다'; retry.textContent = '다시 재생'; retry.style.display = '';});
    document.body.append(root);
    video.play().catch(() => {retry.style.display = '';});
  };
})();
