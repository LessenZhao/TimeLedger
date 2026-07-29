(() => {
  'use strict';

  const documentRoot = document.getElementById('reader-document');
  const toolbar = document.getElementById('selection-toolbar');
  const markdown = window.markdownit({ html: false, linkify: true, typographer: false })
    .use(window.markdownitFootnote);
  let currentDocument = { sections: [], notes: [], allowsAnnotations: false };
  let activeSelection = null;

  function post(type, payload = {}) {
    window.webkit?.messageHandlers?.obsidianReader?.postMessage({ type, ...payload });
  }

  function decodeBase64JSON(encoded) {
    const bytes = Uint8Array.from(atob(encoded), c => c.charCodeAt(0));
    return JSON.parse(new TextDecoder().decode(bytes));
  }

  function mapTextNodes(sectionElement, source) {
    const walker = document.createTreeWalker(sectionElement, NodeFilter.SHOW_TEXT);
    let cursor = 0;
    const sourceLength = source.length;
    for (let node = walker.nextNode(); node; node = walker.nextNode()) {
      const value = node.nodeValue || '';
      if (!value.trim()) continue;
      let position = source.indexOf(value, cursor);
      if (position < 0) continue;
      const end = position + value.length;
      if (end > sourceLength) continue;
      node.__readerSourceStart = position;
      node.__readerSourceEnd = end;
      cursor = end;
    }
  }

  function upgradeTaskItems(scope) {
    for (const item of scope.querySelectorAll('li')) {
      const walker = document.createTreeWalker(item, NodeFilter.SHOW_TEXT);
      const first = walker.nextNode();
      const match = first?.nodeValue?.match(/^\[([ xX])\]\s+/);
      if (!match) continue;
      const remaining = first.splitText(match[0].length);
      first.remove();
      const checkbox = document.createElement('input');
      checkbox.type = 'checkbox';
      checkbox.checked = match[1].toLowerCase() === 'x';
      checkbox.disabled = true;
      item.classList.add('task-list-item');
      remaining.parentNode.insertBefore(checkbox, remaining);
    }
  }

  function sourceSelection(range) {
    const section = range.commonAncestorContainer.nodeType === Node.ELEMENT_NODE
      ? range.commonAncestorContainer.closest('.reader-section')
      : range.commonAncestorContainer.parentElement?.closest('.reader-section');
    if (!section) return null;
    const nodes = [];
    const walker = document.createTreeWalker(section, NodeFilter.SHOW_TEXT);
    for (let node = walker.nextNode(); node; node = walker.nextNode()) {
      if (typeof node.__readerSourceStart !== 'number') continue;
      if (!range.intersectsNode(node)) continue;
      let startOffset = 0;
      let endOffset = node.nodeValue.length;
      if (node === range.startContainer) startOffset = range.startOffset;
      if (node === range.endContainer) endOffset = range.endOffset;
      if (endOffset <= startOffset) continue;
      nodes.push({
        start: node.__readerSourceStart + startOffset,
        end: node.__readerSourceStart + endOffset
      });
    }
    if (!nodes.length) return null;
    const quote = range.toString().replace(/\s+/g, ' ').trim();
    if (!quote) return null;
    const rect = range.getBoundingClientRect();
    return {
      sectionID: section.dataset.sectionId,
      locationUTF16: Math.min(...nodes.map(n => n.start)),
      lengthUTF16: Math.max(...nodes.map(n => n.end)) - Math.min(...nodes.map(n => n.start)),
      quote,
      rect: { x: rect.x, y: rect.y, width: rect.width, height: rect.height }
    };
  }

  function applyHighlights(section, source, notes) {
    const ranges = notes
      .filter(n => n.sectionID === section.id && n.lengthUTF16 > 0)
      .sort((a, b) => b.locationUTF16 - a.locationUTF16);
    for (const note of ranges) {
      const walker = document.createTreeWalker(section.element, NodeFilter.SHOW_TEXT);
      const targets = [];
      for (let node = walker.nextNode(); node; node = walker.nextNode()) {
        if (typeof node.__readerSourceStart !== 'number') continue;
        const start = Math.max(note.locationUTF16, node.__readerSourceStart);
        const end = Math.min(note.locationUTF16 + note.lengthUTF16, node.__readerSourceEnd);
        if (end > start) targets.push({ node, start, end });
      }
      for (const target of targets.reverse()) {
        const localStart = target.start - target.node.__readerSourceStart;
        const localEnd = target.end - target.node.__readerSourceStart;
        const after = target.node.splitText(localEnd);
        const marked = target.node.splitText(localStart);
        const mark = document.createElement('mark');
        mark.className = 'reader-highlight';
        mark.dataset.noteId = note.id;
        marked.parentNode.replaceChild(mark, marked);
        mark.appendChild(marked);
        void after;
      }
    }
    mapTextNodes(section.element, source);
  }

  function render(payload) {
    currentDocument = payload;
    activeSelection = null;
    toolbar.hidden = true;
    documentRoot.replaceChildren();
    for (const section of payload.sections || []) {
      const element = document.createElement('section');
      element.className = 'reader-section markdown-reading-view';
      element.dataset.sectionId = section.id;
      if (section.label) {
        const label = document.createElement('p');
        label.className = 'reader-section-label';
        label.textContent = section.label;
        element.appendChild(label);
      }
      const rendered = document.createElement('div');
      rendered.innerHTML = markdown.render(section.markdown || '');
      upgradeTaskItems(rendered);
      element.appendChild(rendered);
      documentRoot.appendChild(element);
      const mapped = { ...section, element };
      mapTextNodes(element, section.markdown || '');
      applyHighlights(mapped, section.markdown || '', payload.notes || []);
    }
  }

  function updateToolbar() {
    if (!currentDocument.allowsAnnotations) return;
    const selection = window.getSelection();
    if (!selection || selection.rangeCount !== 1 || selection.isCollapsed) {
      activeSelection = null;
      toolbar.hidden = true;
      return;
    }
    activeSelection = sourceSelection(selection.getRangeAt(0));
    if (!activeSelection) {
      toolbar.hidden = true;
      return;
    }
    toolbar.style.left = `${Math.max(8, activeSelection.rect.x)}px`;
    toolbar.style.top = `${Math.max(8, activeSelection.rect.y - 42)}px`;
    toolbar.hidden = false;
  }

  document.addEventListener('selectionchange', () => requestAnimationFrame(updateToolbar));
  // WKWebView can coalesce selectionchange during a pointer drag. Re-check at
  // the end of the gesture so the same browser selection always gets the
  // action surface, without relaxing source-range validation.
  document.addEventListener('mouseup', () => requestAnimationFrame(updateToolbar));
  document.addEventListener('keyup', () => requestAnimationFrame(updateToolbar));
  window.addEventListener('pointerup', () => requestAnimationFrame(updateToolbar));
  // AppKit can apply a native drag selection without delivering a DOM
  // selectionchange to WKWebView. Re-check the browser's actual selection so
  // a valid, mapped selection always receives the same action surface.
  window.setInterval(updateToolbar, 150);
  document.addEventListener('mousedown', event => {
    if (!event.target.closest('.selection-toolbar') && !event.target.closest('.reader-highlight')) {
      toolbar.hidden = true;
    }
  });
  toolbar.addEventListener('mousedown', event => event.preventDefault());
  function performToolbarAction(event) {
    const action = event.target.dataset.action;
    if (!action || !activeSelection) return;
    post(action, activeSelection);
    if (action !== 'note') window.getSelection()?.removeAllRanges();
    activeSelection = null;
    toolbar.hidden = true;
  }
  toolbar.addEventListener('mouseup', performToolbarAction);
  toolbar.addEventListener('click', performToolbarAction);
  document.addEventListener('click', event => {
    const highlight = event.target.closest('.reader-highlight');
    if (highlight?.dataset.noteId) post('editHighlight', { noteID: highlight.dataset.noteId });
    const link = event.target.closest('a');
    if (link?.href) {
      event.preventDefault();
      post('openLink', { href: link.href });
    }
  });

  window.obsidianReader = {
    load(encoded) { render(decodeBase64JSON(encoded)); },
    scrollToSection(id) { document.querySelector(`[data-section-id="${CSS.escape(id)}"]`)?.scrollIntoView({ block: 'start' }); },
    clearSelection() { window.getSelection()?.removeAllRanges(); toolbar.hidden = true; activeSelection = null; }
  };
})();
