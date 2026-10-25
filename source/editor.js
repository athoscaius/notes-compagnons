'use strict';
(()=>{
const editor=document.getElementById('editor'),sidebar=document.getElementById('sidebar'),list=document.getElementById('archive-list');
let session=null,current=null,notes=[],savedRange=null,dirty=false,composing=false,pendingRemote=null,showTrash=false;
const send=(type,data={})=>window.webkit?.messageHandlers.notes.postMessage({type,...data});
const cleanText=s=>String(s??'').replace(/\r\n?/g,'\n').replace(/[\u0000-\u0008\u000b\u000c\u000e-\u001f\u007f\u00ad\u200b\u2060\ufeff\ufffc\u202a-\u202e\u2066-\u2069]/g,'').normalize('NFC');
function publicURL(raw){
 let s=cleanText(raw).trim();if(!s)return '';
 try{const u=new URL(s);if(!['http:','https:','mailto:','tel:'].includes(u.protocol))return '';
  if(u.protocol==='http:'||u.protocol==='https:'){for(const key of [...u.searchParams.keys()])if(/^utm_/i.test(key)||/^(fbclid|gclid|msclkid|mc_cid|mc_eid)$/i.test(key))u.searchParams.delete(key);return u.href;}
  return s;
 }catch{return /^\//.test(s)&&!/^\/\//.test(s)?s:'';}
}
function sanitize(input,headings=false){
 const source=typeof input==='string'?(()=>{const t=document.createElement('template');const start=input.indexOf('<!--StartFragment-->'),end=input.indexOf('<!--EndFragment-->');t.innerHTML=start>=0&&end>start?input.slice(start+20,end):input;return t.content;})():input;
 const classes=new Map();for(const style of source.querySelectorAll?.('style')??[]){for(const m of style.textContent.matchAll(/([^{}]+)\{([^{}]*)\}/g)){for(const selector of m[1].split(',')){const key=selector.trim();if(/^(?:p|span|div)?\.[a-zA-Z0-9_-]+$/.test(key))classes.set(key.replace(/^[^.]+/,''),m[2]);}}}
 const weight=css=>/font-weight\s*:\s*(?:bold|[6-9]00)/i.test(css)||/font(?:-family)?\s*:[^;}]*bold/i.test(css);
 const hidden=css=>/(?:display\s*:\s*none|visibility\s*:\s*hidden|opacity\s*:\s*0(?:[;\s]|$)|font-size\s*:\s*0(?:px|pt|em|[;\s]))/i.test(css);
 const blocked=new Set(['SCRIPT','STYLE','IMG','SVG','MATH','IFRAME','OBJECT','EMBED','LINK','META','BASE','FORM','INPUT','BUTTON','SELECT','TEXTAREA','TEMPLATE','CANVAS','VIDEO','AUDIO','SOURCE']);
 function walk(node,inHeading=false,inBold=false){
  if(node.nodeType===Node.TEXT_NODE)return document.createTextNode(cleanText(node.nodeValue));
  const out=document.createDocumentFragment();if(node.nodeType!==Node.ELEMENT_NODE&&node.nodeType!==Node.DOCUMENT_FRAGMENT_NODE)return out;
  if(node.nodeType===Node.DOCUMENT_FRAGMENT_NODE){for(const child of node.childNodes)out.append(walk(child,inHeading,inBold));return out;}
  const tag=node.tagName;if(blocked.has(tag)||node.hasAttribute('hidden')||node.getAttribute('aria-hidden')==='true')return out;
  const classCSS=[...node.classList].map(c=>(classes.get('.'+c)||'')+(classes.get(node.tagName.toLowerCase()+'.'+c)||'')).join(';');
  const css=(node.getAttribute('style')||'')+';'+classCSS;if(hidden(css))return out;
  const isHeading=/^H[1-6]$/.test(tag)||node.getAttribute('role')==='heading'||[...node.classList].some(c=>/^MsoHeading\d$/i.test(c));
  const headingContext=inHeading||isHeading;
  if(tag==='A'){
   const label=cleanText(node.textContent),url=publicURL(node.getAttribute('href'));
   if(!url)return document.createTextNode(label);
   const plain=label.trim(),looksURL=/^(https?:\/\/|www\.)/i.test(plain);
   return document.createTextNode(!plain||looksURL||plain===url||plain===url.replace(/^https?:\/\//,'')?url:plain+' ('+url+')');
  }
  let target;
  if(isHeading)target=document.createElement(headings&&/^H[1-3]$/.test(tag)?tag.toLowerCase():'p');
  else if(['P','DIV','BLOCKQUOTE','PRE','SECTION','ARTICLE'].includes(tag))target=document.createElement('p');
  else if(tag==='OL'||tag==='UL')target=document.createElement('ul');
  else if(['LI','TABLE','THEAD','TBODY','TFOOT','TR','TD','TH','BR'].includes(tag))target=document.createElement(tag==='TH'?'td':tag.toLowerCase());
  else if(tag==='STRONG'||tag==='B')target=!headingContext?document.createElement('strong'):document.createDocumentFragment();
  else target=document.createDocumentFragment();
  const ownBold=!headingContext&&!inBold&&(weight(css)||tag==='TH')&&tag!=='STRONG'&&tag!=='B';
  let inner=target;
  if(ownBold){const strong=document.createElement('strong');target.append(strong);inner=strong;}
  for(const child of node.childNodes)inner.append(walk(child,headingContext,inBold||ownBold||tag==='B'||tag==='STRONG'));
  return target;
 }
 const cleaned=walk(source),box=document.createElement('div');box.append(cleaned);
 if([...box.children].some(n=>['TD','TH'].includes(n.tagName))){const table=document.createElement('table'),row=table.insertRow();while(box.firstChild)row.append(box.firstChild);box.append(table);}
 else if([...box.children].some(n=>['TR','TBODY','THEAD','TFOOT'].includes(n.tagName))){const table=document.createElement('table');while(box.firstChild)table.append(box.firstChild);box.append(table);}
 for(const p of box.querySelectorAll('p')){if(p.querySelector('p,ul,table'))p.replaceWith(...p.childNodes);}
 return box;
}
function runsFor(node,bold=false){
 const runs=[];function add(text,b){text=cleanText(text);if(!text)return;const last=runs[runs.length-1];if(last&&last.bold===b)last.text+=text;else runs.push({text,bold:b});}
 function walk(n,b){if(n.nodeType===Node.TEXT_NODE){add(n.nodeValue,b);return;}if(n.nodeType!==Node.ELEMENT_NODE&&n.nodeType!==Node.DOCUMENT_FRAGMENT_NODE)return;const t=n.tagName;if(t==='UL'||t==='OL'||t==='TABLE')return;if(t==='BR'){add('\n',b);return;}for(const c of n.childNodes){if(c.nodeType===1&&['P','DIV'].includes(c.tagName)&&runs.length)add('\n',b);walk(c,b||t==='STRONG'||t==='B');}}
 walk(node,bold);return runs;
}
function blocksFor(box){
 const blocks=[];let inline=document.createElement('p');
 const flush=()=>{if(inline.childNodes.length){blocks.push({kind:'paragraph',level:0,runs:runsFor(inline)});inline=document.createElement('p');}};
 function emit(node,depth=0){
  if(node.nodeType===Node.TEXT_NODE){inline.append(node.cloneNode(true));return;}
  if(node.nodeType!==Node.ELEMENT_NODE)return;
  const tag=node.tagName;
  if(tag==='TABLE'){flush();blocks.push({kind:'table',rows:[...node.rows].map(row=>[...row.cells].map(cell=>({runs:runsFor(cell)})))});}
  else if(tag==='UL'||tag==='OL'){flush();for(const li of node.children)if(li.tagName==='LI'){blocks.push({kind:'bullet',level:Math.min(depth,5),runs:runsFor(li)});for(const ul of li.children)if(ul.tagName==='UL')emit(ul,depth+1);}}
  else if(tag==='LI'){flush();blocks.push({kind:'bullet',level:depth,runs:runsFor(node)});}
  else if(['P','DIV','H1','H2','H3'].includes(tag)){flush();blocks.push({kind:'paragraph',level:/^H[1-3]$/.test(tag)?Number(tag.slice(1)):0,runs:runsFor(node)});}
  else inline.append(node.cloneNode(true));
 }
 for(const n of box.childNodes)emit(n);flush();return blocks;
}
function plainFor(blocks){return blocks.map(b=>b.kind==='table'?b.rows.map(row=>row.map(cell=>cell.runs.map(r=>r.text).join('')).join('\t')).join('\n'):(b.kind==='bullet'?'• ':'')+(b.runs??[]).map(r=>r.text).join('')).join('\n').replace(/\n{3,}/g,'\n\n');}
function snapshot(){const box=sanitize(editor.cloneNode(true),true); // clone contains the outer article, never user metadata
 const inner=box.children.length===1&&box.firstElementChild.tagName==='P'&&box.firstElementChild.querySelector('p,h1,h2,h3,table,ul')?box.firstElementChild:box;
 const blocks=blocksFor(inner),plain=plainFor(blocks);return {html:inner.innerHTML,plain,blocks};}
function changed(){if(composing)return;dirty=true;const data=snapshot();editor.classList.toggle('is-empty',!data.plain.trim()&&!editor.querySelector('table'));document.getElementById('save-status').textContent='Enregistrement…';send('change',{...data,session});updateTools();}
function remember(){const s=getSelection();if(s.rangeCount&&editor.contains(s.anchorNode))savedRange=s.getRangeAt(0).cloneRange();}
function restore(){editor.focus();const s=getSelection();if(savedRange&&editor.contains(savedRange.commonAncestorContainer)){s.removeAllRanges();s.addRange(savedRange);}else{const range=document.createRange();range.selectNodeContents(editor);range.collapse(false);s.removeAllRanges();s.addRange(range);}}
function insert(box){restore();document.execCommand('insertHTML',false,box.innerHTML);remember();changed();}
function acceptPaste(payload){const box=payload.html?sanitize(payload.html,false):(()=>{const x=document.createElement('div');for(const line of cleanText(payload.plain).split('\n')){const p=document.createElement('p');p.textContent=line;if(!line)p.append(document.createElement('br'));x.append(p);}return x;})();insert(box);}
function requestPaste(){remember();send('paste');}
function updateTools(){const s=getSelection();if(!s.rangeCount||!editor.contains(s.anchorNode))return;document.getElementById('bold').classList.toggle('active',document.queryCommandState('bold'));document.getElementById('bold').setAttribute('aria-pressed',String(document.queryCommandState('bold')));let n=s.anchorNode.nodeType===1?s.anchorNode:s.anchorNode.parentElement;const h=n?.closest('h1,h2,h3');for(const b of document.querySelectorAll('[data-heading]'))b.classList.toggle('active',Number(b.dataset.heading)===(h?Number(h.tagName.slice(1)):0));}
function command(name,value){restore();document.execCommand(name,false,value);remember();changed();}
function heading(level){command('formatBlock',level?'H'+level:'P');}
function createTable(cols,rows){cols=Math.max(1,Math.min(12,Math.floor(Number(cols)||1)));rows=Math.max(1,Math.min(50,Math.floor(Number(rows)||1)));const box=document.createElement('div'),table=document.createElement('table');for(let r=0;r<rows;r++){const row=table.insertRow();for(let c=0;c<cols;c++){const cell=row.insertCell();cell.innerHTML='<p><br></p>';}}const marker='table-'+Date.now();table.dataset.insert=marker;box.append(table);const p=document.createElement('p');p.innerHTML='<br>';box.append(p);document.getElementById('table-picker').hidden=true;document.getElementById('table').setAttribute('aria-expanded','false');insert(box);const range=document.createRange();const actual=editor.querySelector(`table[data-insert="${marker}"]`);if(!actual)return;actual.removeAttribute("data-insert");range.selectNodeContents(actual.rows[0].cells[0].firstChild);range.collapse(true);getSelection().removeAllRanges();getSelection().addRange(range);remember();}
function dateLabel(iso){const d=new Date(iso),today=new Date(),yesterday=new Date();yesterday.setDate(today.getDate()-1);const day=x=>x.toDateString();if(day(d)===day(today))return 'Aujourd’hui';if(day(d)===day(yesterday))return 'Hier';return new Intl.DateTimeFormat('fr-FR',{weekday:'long',day:'numeric',month:'long',year:d.getFullYear()===today.getFullYear()?undefined:'numeric'}).format(d);}
function renderArchives(){
 const scroll=list.scrollTop;list.replaceChildren();let group=null;
 const visible=notes.filter(n=>showTrash?!!n.deletedAt:!n.deletedAt).sort((a,b)=>new Date(showTrash?b.deletedAt:b.createdAt)-new Date(showTrash?a.deletedAt:a.createdAt));
 for(const note of visible){
  const label=dateLabel(showTrash?note.deletedAt:note.createdAt);if(label!==group){const h=document.createElement('div');h.className='date-group';h.textContent=label;list.append(h);group=label;}
  const row=document.createElement('div');row.className='note-row';
  const item=document.createElement(showTrash?'div':'button');item.className='note-item'+(note.id===current?' active':'')+(showTrash?' trash-preview':'');item.dataset.id=note.id;
  const preview=document.createElement('span');preview.className='note-preview';preview.textContent=note.plain.trim().split('\n').filter(Boolean).slice(0,2).join(' ')||note.fallback||'Note vide';
  const time=document.createElement('span');time.className='note-time';time.textContent=new Intl.DateTimeFormat('fr-FR',{hour:'2-digit',minute:'2-digit'}).format(new Date(note.createdAt));item.append(preview,time);if(!showTrash)item.addEventListener('click',()=>send('open',{id:note.id}));
  const action=document.createElement('button');action.className=showTrash?'restore-action':'trash-action';action.title=showTrash?'Restaurer la note':'Placer dans la corbeille';action.setAttribute('aria-label',action.title+' : '+preview.textContent.slice(0,65));
  if(showTrash)action.textContent='Restaurer';else action.innerHTML='<svg viewBox="0 0 24 24" aria-hidden="true"><path d="M4 6h16M9 6V3h6v3M6 6l1 15h10l1-15M10 10v7m4-7v7"/></svg>';
  action.addEventListener('click',()=>send(showTrash?'restore':'trash',{id:note.id}));row.append(item,action);list.append(row);
 }
 document.getElementById('archive-title').textContent=showTrash?'CORBEILLE':'ARCHIVES';document.getElementById('note-count').textContent=String(visible.length);document.getElementById('trash-count').textContent=String(notes.filter(n=>n.deletedAt).length);document.getElementById('trash-toggle').setAttribute('aria-pressed',String(showTrash));document.getElementById('empty-trash').hidden=!showTrash||!visible.length;
 if(!visible.length){const empty=document.createElement('div');empty.className='empty-archive';empty.textContent=showTrash?'La corbeille est vide.':'Vos notes apparaîtront ici, au fil des jours.';list.append(empty);}list.scrollTop=scroll;
}
function setNote(note,token){if(token)session=token;current=note?.id??null;const box=sanitize(note?.html||'<p><br></p>',true);editor.replaceChildren(...box.childNodes);if(!editor.childNodes.length)editor.innerHTML='<p><br></p>';savedRange=null;dirty=false;editor.classList.toggle('is-empty',!(note?.plain??'').trim()&&!editor.querySelector('table'));document.getElementById('save-status').textContent=note?'Enregistrée sur ce Mac':'Prête à écrire';renderArchives();countWords();editor.focus();const caret=document.createRange();caret.selectNodeContents(editor.querySelector('p,h1,h2,h3,li,td,th')||editor);caret.collapse(true);const selection=getSelection();selection.removeAllRanges();selection.addRange(caret);remember();}
function countWords(){const s=cleanText(editor.innerText).trim(),count=s?s.split(/\s+/u).length:0;document.getElementById('word-count').textContent=count+' mot'+(count>1?'s':'');}
editor.addEventListener('input',()=>{changed();countWords();});editor.addEventListener('compositionstart',()=>composing=true);editor.addEventListener('compositionend',()=>{composing=false;changed();});
function autoBullet(){
 const selection=getSelection();if(composing||!selection.isCollapsed||!selection.rangeCount)return false;
 const node=selection.anchorNode,block=(node.nodeType===1?node:node.parentElement)?.closest('p,div');
 if(!block||block===editor||!editor.contains(block)||block.closest('li'))return false;
 const prefix=document.createRange();prefix.selectNodeContents(block);prefix.setEnd(selection.anchorNode,selection.anchorOffset);
 if(prefix.toString()!=='-')return false;
 prefix.deleteContents();selection.removeAllRanges();selection.addRange(prefix);remember();command('insertUnorderedList');return true;
}
editor.addEventListener('beforeinput',e=>{if(e.inputType==='insertText'&&e.data===' '&&autoBullet()){e.preventDefault();return;}if(/^format/.test(e.inputType)&&!['formatBold','formatBlock'].includes(e.inputType))e.preventDefault();});
editor.addEventListener('paste',e=>{e.preventDefault();remember();if(window.webkit)requestPaste();else acceptPaste({html:e.clipboardData.getData('text/html'),plain:e.clipboardData.getData('text/plain')});});
for(const type of ['copy','cut'])editor.addEventListener(type,e=>{const s=getSelection();if(!s.rangeCount||s.isCollapsed)return;const clean=sanitize(s.getRangeAt(0).cloneContents(),false);e.preventDefault();e.clipboardData.setData('text/html',clean.innerHTML);e.clipboardData.setData('text/plain',plainFor(blocksFor(clean)));if(type==='cut'){document.execCommand('delete');changed();}});
editor.addEventListener('drop',e=>{e.preventDefault();remember();acceptPaste({plain:e.dataTransfer.getData('text/plain'),html:e.dataTransfer.getData('text/html')});});
editor.addEventListener('keydown',e=>{if((e.metaKey||e.ctrlKey)&&!e.altKey&&!e.shiftKey&&e.key.toLowerCase()==='b'){e.preventDefault();command('bold');return;}if((e.metaKey||e.ctrlKey)&&['i','u','k'].includes(e.key.toLowerCase()))e.preventDefault();if(e.key==='Tab'){const cell=getSelection().anchorNode?.parentElement?.closest('td,th');if(cell){e.preventDefault();const table=cell.closest('table'),cells=[...table.querySelectorAll('td,th')];let next=cells[cells.indexOf(cell)+(e.shiftKey?-1:1)];if(!next&&!e.shiftKey&&table.rows.length<50){const row=table.insertRow();for(let c=0;c<cell.parentElement.cells.length;c++)row.insertCell().innerHTML='<p><br></p>';next=row.cells[0];changed();}if(next){const range=document.createRange();range.selectNodeContents(next);range.collapse(true);getSelection().removeAllRanges();getSelection().addRange(range);remember();}}}});
document.addEventListener('selectionchange',()=>{remember();updateTools();});
for(const button of document.querySelectorAll('.format-bar button'))button.addEventListener('mousedown',e=>{remember();if(button.id!=='insert-table'&&!button.closest('#table-picker'))e.preventDefault();});
document.getElementById('bold').addEventListener('click',()=>command('bold'));
document.getElementById('bullet').addEventListener('click',()=>command('insertUnorderedList'));
for(const b of document.querySelectorAll('[data-heading]'))b.addEventListener('click',()=>heading(Number(b.dataset.heading)));
document.getElementById('table').addEventListener('click',()=>{const p=document.getElementById('table-picker');p.hidden=!p.hidden;document.getElementById('table').setAttribute('aria-expanded',String(!p.hidden));});
const grid=document.getElementById('table-grid');for(let r=1;r<=8;r++)for(let c=1;c<=8;c++){const b=document.createElement('button');b.title=`${c} colonne${c>1?'s':''} × ${r} ligne${r>1?'s':''}`;b.setAttribute('aria-label',b.title);b.addEventListener('mouseenter',()=>{for(const [i,n]of[...grid.children].entries())n.classList.toggle('lit',Math.floor(i/8)<r&&i%8<c);document.getElementById('grid-label').textContent=b.title;});b.addEventListener('click',()=>createTable(c,r));grid.append(b);}
document.getElementById('insert-table').addEventListener('click',()=>createTable(document.getElementById('table-cols').value,document.getElementById('table-rows').value));
document.getElementById('archive-toggle').addEventListener('click',()=>{sidebar.hidden=!sidebar.hidden;if(!sidebar.hidden)renderArchives();document.getElementById('archive-toggle').setAttribute('aria-expanded',String(!sidebar.hidden));});
document.getElementById('trash-toggle').addEventListener('click',()=>{showTrash=!showTrash;list.scrollTop=0;renderArchives();});
document.getElementById('empty-trash').addEventListener('click',()=>send('emptyTrash'));
document.getElementById('new-note').addEventListener('click',()=>send('new'));
document.getElementById('export').addEventListener('click',()=>send('export',snapshot()));
document.addEventListener('keydown',e=>{if(e.key==='Escape'){document.getElementById('table-picker').hidden=true;editor.focus();}if((e.metaKey||e.ctrlKey)&&e.shiftKey&&e.key.toLowerCase()==='a'){e.preventDefault();document.getElementById('archive-toggle').click();}});
window.Notes={bootstrap(data){notes=data.notes;setNote(null,data.session);},setNote,saved(data){if(data.session!==session)return;current=data.id;dirty=false;notes=data.notes;document.getElementById('save-status').textContent='Enregistrée sur ce Mac';document.getElementById('save-status').classList.remove('save-error');if(!sidebar.hidden)renderArchives();},archives(data){notes=data.notes;renderArchives();if(current&&!notes.some(n=>n.id===current&&!n.deletedAt))setNote(null,data.session);},acceptPaste,snapshot,newNote(){send('new');},focus(){editor.focus();},exportBusy(value){document.getElementById('export').classList.toggle('export-busy',value);},error(message){document.getElementById('save-status').textContent=message;document.getElementById('save-status').classList.add('save-error');},exported(message){document.getElementById('save-status').textContent=message;},test:{cleanText,publicURL,sanitize,blocksFor,plainFor,setHTML(html){setNote({id:null,html,plain:html});},copyHTML(){const range=document.createRange();range.selectNodeContents(editor);return sanitize(range.cloneContents(),false).innerHTML;},createTable}};
editor.classList.add('is-empty');send('ready');
})();
