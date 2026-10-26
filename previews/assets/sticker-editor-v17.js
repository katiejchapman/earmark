const gemShapes = ['heart', 'flower', 'diamond', 'round', 'butterfly', 'star', 'petal-flower', 'moon'];
const gemColors = ['green', 'blue', 'pink', 'yellow', 'purple', 'silver'];
const stickerCatalog = gemShapes.flatMap(shape => gemColors.map(color => ({
  key: shape + '-' + color,
  src: '../ios/Design/approved/gems/Gem_' + shape.replaceAll('-', '_') + '_' + color + '.svg',
  label: color + ' ' + shape.replaceAll('-', ' ')
})));
const originals = ['heart', 'flower', 'diamond'].map(shape => ({
  key: shape + '-original',
  src: '../ios/Design/approved/gems/Gem_' + shape + '_' + (shape === 'flower' ? 'blue' : 'pink') + '.svg',
  label: shape
}));
const stickerByKey = Object.fromEntries([...stickerCatalog, ...originals].map(item => [item.key, item]));
const layoutKey = 'earmark-preview-v17::stereo-stickers';
const initialLayout = [
  {id: 'heart-default', key: 'heart-original', x: .085, y: .61, size: 28, rotation: 0},
  {id: 'flower-default', key: 'flower-original', x: .17, y: .69, size: 26, rotation: 0},
  {id: 'diamond-default', key: 'diamond-original', x: .91, y: .68, size: 28, rotation: 0}
];
let savedLayout = initialLayout;
try {
  const raw = JSON.parse(localStorage.getItem(layoutKey));
  if (Array.isArray(raw) && raw.every(item => stickerByKey[item.key] &&
    Number.isFinite(item.x) && Number.isFinite(item.y) && item.x >= 0 && item.x <= 1 &&
    item.y >= 0 && item.y <= 1 && item.size >= 18 && item.size <= 120 &&
    Number.isFinite(item.rotation ?? 0))) savedLayout = raw;
} catch {}
let draft = structuredClone(savedLayout), decorating = false, selectedSticker = null;
let active = null, edgeFrame = null;
const pointers = new Map();
const clamp = (value, min, max) => Math.max(min, Math.min(max, value));
const normalAngle = angle => ((angle + 180) % 360 + 360) % 360 - 180;
const point = event => ({x: event.clientX, y: event.clientY});
const distance = (a, b) => Math.hypot(a.x - b.x, a.y - b.y);
const angleBetween = (a, b) => Math.atan2(b.y - a.y, b.x - a.x) * 180 / Math.PI;
const midpoint = (a, b) => ({x: (a.x + b.x) / 2, y: (a.y + b.y) / 2});
function inside(rect, x, y) { return x >= rect.left && x <= rect.right && y >= rect.top && y <= rect.bottom; }
function itemByID(id) { return draft.find(item => item.id === id); }
function stickerNode(id) { return [...$('stickerLayer').children].find(node => node.dataset.stickerId === id); }
function boundItem(item) {
  item.size = clamp(item.size, 18, 120);
  item.rotation = normalAngle(item.rotation ?? 0);
  const rect = $('stereo').getBoundingClientRect();
  const rad = item.rotation * Math.PI / 180;
  const extent = item.size / 2 * (Math.abs(Math.cos(rad)) + Math.abs(Math.sin(rad))) + 4;
  item.x = clamp(item.x, extent / rect.width, 1 - extent / rect.width);
  item.y = clamp(item.y, extent / rect.height, 1 - extent / rect.height);
}
function paintItem(item) {
  const node = stickerNode(item.id);
  if (!node) return;
  node.style.left = item.x * 100 + '%'; node.style.top = item.y * 100 + '%';
  node.style.width = item.size + 'px'; node.style.height = item.size + 'px';
  node.style.transform = 'translate(-50%,-50%) rotate(' + (item.rotation ?? 0) + 'deg)';
}
function updateEditControls() {
  const item = itemByID(selectedSticker);
  for (const node of $('stickerLayer').children) node.classList.toggle('selected', decorating && node.dataset.stickerId === selectedSticker);
}
function selectSticker(id) { selectedSticker = id; updateEditControls(); }
function renderStickers() {
  const layer = $('stickerLayer'); layer.replaceChildren();
  for (const item of draft) {
    item.rotation ??= 0;
    boundItem(item);
    const node = document.createElement('button');
    node.className = 'placed-sticker'; node.dataset.stickerId = item.id;
    node.setAttribute('aria-label', 'Edit ' + stickerByKey[item.key].label + ' sticker');
    node.tabIndex = decorating ? 0 : -1;
    const img = document.createElement('img'); img.src = stickerByKey[item.key].src; img.alt = ''; img.draggable = false;
    node.append(img);
    for (const mode of ['resize', 'rotate']) {
      const handle = document.createElement('span');
      handle.className = 'sticker-handle ' + mode + '-handle';
      handle.textContent = mode === 'resize' ? '↔' : '↻';
      handle.setAttribute('aria-hidden', 'true');
      handle.onpointerdown = event => { event.stopPropagation(); beginPlaced(event, item.id, mode); };
      node.append(handle);
    }
    node.onpointerdown = event => beginPlaced(event, item.id, 'move');
    node.onkeydown = event => {
      if (!decorating) return;
      selectSticker(item.id);
      if (event.key === 'Delete' || event.key === 'Backspace') {
        event.preventDefault(); removeSticker(item.id); return;
      }
      const step = event.shiftKey ? 10 : 2;
      const rect = $('stereo').getBoundingClientRect();
      const keys = {ArrowLeft: [-step, 0], ArrowRight: [step, 0], ArrowUp: [0, -step], ArrowDown: [0, step]};
      if (keys[event.key]) { item.x += keys[event.key][0] / rect.width; item.y += keys[event.key][1] / rect.height; }
      else if (event.key === '+' || event.key === '=') item.size += 3;
      else if (event.key === '-') item.size -= 3;
      else if (event.key === '[') item.rotation -= 5;
      else if (event.key === ']') item.rotation += 5;
      else return;
      event.preventDefault(); boundItem(item); paintItem(item); updateEditControls();
    };
    layer.append(node); paintItem(item);
  }
  updateEditControls();
}
function startDecorating() {
  decorating = true; $('stereo').classList.add('decorating'); $('stickerPanel').hidden = false;
  $('decorate').setAttribute('aria-expanded', 'true'); renderStickers();
}
function doneDecorating() {
  if (active) return;
  try { localStorage.setItem(layoutKey, JSON.stringify(draft)); savedLayout = structuredClone(draft); }
  catch { toast('This browser could not save the decorations'); return; }
  decorating = false; selectedSticker = null; $('stereo').classList.remove('decorating');
  $('stickerPanel').hidden = true; $('decorate').setAttribute('aria-expanded', 'false');
  if (location.hash === '#decorate') { try { history.replaceState(null, '', location.pathname + location.search); } catch {} }
  renderStickers(); toast('Decorations saved');
}
function removeSticker(id) {
  draft = draft.filter(item => item.id !== id);
  if (selectedSticker === id) selectedSticker = null;
  renderStickers(); $('sheetHint').textContent = 'gem removed · tap done to save';
}
$('decorate').onclick = () => decorating ? doneDecorating() : startDecorating();
$('decorateDone').onclick = doneDecorating;
let stickerPage=0;
const pageCount=Math.ceil(stickerCatalog.length/5);
function renderSheet(){const host=$('stickerSheet');host.replaceChildren();stickerCatalog.slice(stickerPage*5,stickerPage*5+5).forEach((item,index)=>{const node=document.createElement('button');node.className='sheet-sticker';node.dataset.stickerKey=item.key;node.setAttribute('aria-label','Drag '+item.label+' gem onto stereo');node.style.setProperty('--tilt',[-5,3,-3,4,-4][index]+'deg');const img=document.createElement('img');img.src=item.src;img.alt='';img.draggable=false;node.append(img);node.onpointerdown=event=>beginSheet(event,item.key);host.append(node)});const pager=$('stickerPager');pager.replaceChildren();for(let n=0;n<pageCount;n++){const dot=document.createElement('button');dot.setAttribute('aria-label','Sticker page '+(n+1)+' of '+pageCount);dot.setAttribute('aria-current',n===stickerPage?'true':'false');dot.onclick=()=>goPage(n);pager.append(dot)}}
function goPage(n){stickerPage=clamp(n,0,pageCount-1);renderSheet();$('stickerSheet').animate([{opacity:.5,transform:'translateX(8px)'},{opacity:1,transform:'translateX(0)'}],{duration:160})}
renderSheet();
function centerOf(item) {
  const rect = $('stereo').getBoundingClientRect();
  return {x: rect.left + item.x * rect.width, y: rect.top + item.y * rect.height};
}
function capture(event) { try { event.currentTarget.setPointerCapture(event.pointerId); } catch {} }
function prepareMove(origin) {
  const item = itemByID(active.id), center = centerOf(item);
  active.mode = 'move'; active.offset = {x: origin.x - center.x, y: origin.y - center.y};
}
function beginPlaced(event, id, mode) {
  if (!decorating || event.button !== 0) return;
  event.preventDefault(); event.stopPropagation();
  if (active) {
    if (active.kind === 'placed' && active.id === id && !pointers.has(event.pointerId)) {
      pointers.set(event.pointerId, point(event)); capture(event); preparePinch();
    }
    return;
  }
  const item = itemByID(id); selectSticker(id);
  active = {kind: 'placed', id, mode, initial: structuredClone(item), x: event.clientX, y: event.clientY};
  pointers.set(event.pointerId, point(event)); capture(event);
  if (mode === 'move') prepareMove(point(event));
  else {
    const center = centerOf(item);
    active.startDistance = Math.max(1, distance(point(event), center));
    active.startAngle = angleBetween(center, point(event)); active.base = structuredClone(item);
  }
  document.body.classList.add('dragging-sticker'); edgeFrame = requestAnimationFrame(edgeScroll);
}
// The second finger can land just outside a small gem while the first holds it.
$('stereo').addEventListener('pointerdown', event => {
  if (!decorating || event.pointerType !== 'touch' || active?.kind !== 'placed' || pointers.has(event.pointerId)) return;
  event.preventDefault(); event.stopPropagation(); pointers.set(event.pointerId, point(event)); capture(event); preparePinch();
}, true);
function preparePinch() {
  if (pointers.size < 2 || active?.kind !== 'placed') return;
  const [a, b] = [...pointers.values()];
  active.mode = 'pinch'; active.pinch = {distance: Math.max(1, distance(a, b)), angle: angleBetween(a, b), center: midpoint(a, b), base: structuredClone(itemByID(active.id))};
}
function beginSheet(event,key){if(!decorating||active||event.button!==0)return;event.preventDefault();const ghost=document.createElement('img');ghost.className='drag-ghost';ghost.src=stickerByKey[key].src;document.body.append(ghost);active={kind:'sheet',key,ghost,pointerId:event.pointerId,x:event.clientX,y:event.clientY,origin:point(event),offset:{x:0,y:0},size:35,rotation:0,paging:false,transformed:false};pointers.set(event.pointerId,point(event));capture(event);document.body.classList.add('dragging-sticker');movePointer(event);edgeFrame=requestAnimationFrame(edgeScroll)}
function prepareSheetPinch(){if(active?.kind!=='sheet'||pointers.size<2)return;const[a,b]=[...pointers.values()];active.paging=false;active.transformed=true;active.sheetPinch={distance:Math.max(1,distance(a,b)),angle:angleBetween(a,b),mid:midpoint(a,b),size:active.size,rotation:active.rotation,x:active.x,y:active.y}}
document.addEventListener('pointerdown',event=>{if(active?.kind!=='sheet'||event.pointerType!=='touch'||pointers.has(event.pointerId))return;event.preventDefault();event.stopPropagation();pointers.set(event.pointerId,point(event));capture(event);prepareSheetPinch()},true);
function updateDropState() {
  if (!active) return;
  const over = inside($('stereo').getBoundingClientRect(), active.x, active.y);
  $('stereo').classList.toggle('stereo-drop-target', active.kind === 'sheet' && over);
  $('stickerTrash').classList.toggle('over', active.kind === 'placed' && active.mode === 'move' && inside($('stickerTrash').getBoundingClientRect(), active.x, active.y));
}
function edgeScroll() {
  if (!active) return;
  if (active.kind === 'sheet' || active.mode === 'move') {
    const dy = active.y < 50 ? -9 : active.y > innerHeight - 50 ? 9 : 0;
    if (dy) { window.scrollBy(0, dy); updateDropState(); }
  }
  edgeFrame = requestAnimationFrame(edgeScroll);
}
function movePointer(event) {
  if (!active) return;
  if(active.kind==='sheet'){
    if(!pointers.has(event.pointerId))return;event.preventDefault();pointers.set(event.pointerId,point(event));
    if(pointers.size>=2&&active.sheetPinch){const[a,b]=[...pointers.values()],pin=active.sheetPinch,mid=midpoint(a,b);active.size=clamp(pin.size*distance(a,b)/pin.distance,18,120);active.rotation=pin.rotation+normalAngle(angleBetween(a,b)-pin.angle);active.x=pin.x+mid.x-pin.mid.x;active.y=pin.y+mid.y-pin.mid.y}
    else{active.x=event.clientX-active.offset.x;active.y=event.clientY-active.offset.y;const dx=event.clientX-active.origin.x,dy=event.clientY-active.origin.y;if(!active.transformed&&Math.abs(dx)>16&&Math.abs(dx)>Math.abs(dy)*1.3&&Math.abs(dy)<30)active.paging=true}
    active.ghost.hidden=active.paging;active.ghost.style.left=active.x+'px';active.ghost.style.top=active.y+'px';active.ghost.style.width=active.size+'px';active.ghost.style.height=active.size+'px';active.ghost.style.transform='translate(-50%,-50%) rotate('+active.rotation+'deg)';updateDropState();return;
  }
  if (!pointers.has(event.pointerId)) return;
  event.preventDefault(); pointers.set(event.pointerId, point(event)); active.x = event.clientX; active.y = event.clientY;
  const item = itemByID(active.id), rect = $('stereo').getBoundingClientRect();
  if (active.mode === 'pinch' && pointers.size >= 2) {
    const [a, b] = [...pointers.values()], pin = active.pinch, mid = midpoint(a, b);
    item.size = pin.base.size * distance(a, b) / pin.distance;
    item.rotation = pin.base.rotation + normalAngle(angleBetween(a, b) - pin.angle);
    item.x = pin.base.x + (mid.x - pin.center.x) / rect.width;
    item.y = pin.base.y + (mid.y - pin.center.y) / rect.height;
  } else if (active.mode === 'move') {
    item.x = (event.clientX - rect.left - active.offset.x) / rect.width;
    item.y = (event.clientY - rect.top - active.offset.y) / rect.height;
  } else {
    const center = centerOf(active.base);
    if (active.mode === 'resize') item.size = active.base.size * distance(center, point(event)) / active.startDistance;
    if (active.mode === 'rotate') item.rotation = active.base.rotation + normalAngle(angleBetween(center, point(event)) - active.startAngle);
  }
  boundItem(item); paintItem(item); updateEditControls(); updateDropState();
}
function cleanup() {
  if (active?.ghost) active.ghost.remove();
  cancelAnimationFrame(edgeFrame); active = null; pointers.clear();
  $('stereo').classList.remove('stereo-drop-target'); $('stickerTrash').classList.remove('over');
  document.body.classList.remove('dragging-sticker'); renderStickers();
}
function finishPointer(event, cancelled = false) {
  if (!active) return;
  if(active.kind==='sheet'){
    if(!pointers.has(event.pointerId))return;pointers.delete(event.pointerId);if(pointers.size&&!cancelled){const[id,p]=[...pointers.entries()][0];active.pointerId=id;active.offset={x:p.x-active.x,y:p.y-active.y};active.sheetPinch=null;return}
    if(!cancelled&&active.paging){goPage(stickerPage+(active.x<active.origin.x?1:-1));cleanup();return}
    const rect=$('stereo').getBoundingClientRect();if(!cancelled&&inside(rect,active.x,active.y)){const item={id:crypto.randomUUID(),key:active.key,size:active.size,rotation:active.rotation,x:(active.x-rect.left)/rect.width,y:(active.y-rect.top)/rect.height};boundItem(item);draft.push(item);selectedSticker=item.id}cleanup();return;
  }
  if (!pointers.has(event.pointerId)) return;
  pointers.delete(event.pointerId);
  if (cancelled) { Object.assign(itemByID(active.id), active.initial); cleanup(); return; }
  if (pointers.size) { prepareMove([...pointers.values()][0]); return; }
  if (active.mode === 'move' && inside($('stickerTrash').getBoundingClientRect(), event.clientX, event.clientY)) {
    const id = active.id; cleanup(); removeSticker(id); return;
  }
  if (active.mode === 'move' && !inside($('stereo').getBoundingClientRect(), event.clientX, event.clientY)) Object.assign(itemByID(active.id), active.initial);
  cleanup();
}
document.addEventListener('pointermove', movePointer, {passive: false});
document.addEventListener('pointerup', event => finishPointer(event));
document.addEventListener('pointercancel', event => finishPointer(event, true));
window.addEventListener('blur', () => { if (active) { if (active.kind === 'placed') Object.assign(itemByID(active.id), active.initial); cleanup(); } });
$('stereo').addEventListener('wheel', event => {
  if (!decorating || !selectedSticker || (!event.ctrlKey && !event.altKey)) return;
  event.preventDefault(); const item = itemByID(selectedSticker);
  if (event.altKey) item.rotation += event.deltaY * .2; else item.size *= Math.exp(-event.deltaY * .005);
  boundItem(item); paintItem(item); updateEditControls();
}, {passive: false});
renderStickers();
if (location.hash === '#decorate') startDecorating();
