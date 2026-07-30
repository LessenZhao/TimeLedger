(() => {
  'use strict';

  const documentRoot = document.getElementById('reader-document');
  const toolbar = document.getElementById('selection-toolbar');
  const markdown = window.markdownit({ html: false, linkify: true, typographer: false })
    .use(window.markdownitFootnote);
  let currentDocument = { sections: [], notes: [], allowsAnnotations: false };
  let annotators = [];
  let pendingSelection = null;
  let diagnosticEvents = [];

  function recordDiagnostic(event) {
    diagnosticEvents = [...diagnosticEvents.slice(-3), event];
    documentRoot.setAttribute('aria-label', diagnosticEvents.join(', '));
  }

  function post(type, payload = {}) {
    window.webkit?.messageHandlers?.obsidianReader?.postMessage({ type, ...payload });
  }

  function decodeBase64JSON(encoded) {
    const bytes = Uint8Array.from(atob(encoded), c => c.charCodeAt(0));
    return JSON.parse(new TextDecoder().decode(bytes));
  }

  function sha256(text) {
    const bytes = new TextEncoder().encode(text);
    const bitLength = BigInt(bytes.length) * 8n;
    const paddedLength = Math.ceil((bytes.length + 9) / 64) * 64;
    const data = new Uint8Array(paddedLength);
    data.set(bytes);
    data[bytes.length] = 0x80;
    let remainingLength = bitLength;
    for (let index = 0; index < 8; index += 1) {
      data[paddedLength - 1 - index] = Number(remainingLength & 0xffn);
      remainingLength >>= 8n;
    }

    const constants = [
      0x428a2f98, 0x71374491, 0xb5c0fbcf, 0xe9b5dba5,
      0x3956c25b, 0x59f111f1, 0x923f82a4, 0xab1c5ed5,
      0xd807aa98, 0x12835b01, 0x243185be, 0x550c7dc3,
      0x72be5d74, 0x80deb1fe, 0x9bdc06a7, 0xc19bf174,
      0xe49b69c1, 0xefbe4786, 0x0fc19dc6, 0x240ca1cc,
      0x2de92c6f, 0x4a7484aa, 0x5cb0a9dc, 0x76f988da,
      0x983e5152, 0xa831c66d, 0xb00327c8, 0xbf597fc7,
      0xc6e00bf3, 0xd5a79147, 0x06ca6351, 0x14292967,
      0x27b70a85, 0x2e1b2138, 0x4d2c6dfc, 0x53380d13,
      0x650a7354, 0x766a0abb, 0x81c2c92e, 0x92722c85,
      0xa2bfe8a1, 0xa81a664b, 0xc24b8b70, 0xc76c51a3,
      0xd192e819, 0xd6990624, 0xf40e3585, 0x106aa070,
      0x19a4c116, 0x1e376c08, 0x2748774c, 0x34b0bcb5,
      0x391c0cb3, 0x4ed8aa4a, 0x5b9cca4f, 0x682e6ff3,
      0x748f82ee, 0x78a5636f, 0x84c87814, 0x8cc70208,
      0x90befffa, 0xa4506ceb, 0xbef9a3f7, 0xc67178f2
    ];
    const state = [
      0x6a09e667, 0xbb67ae85, 0x3c6ef372, 0xa54ff53a,
      0x510e527f, 0x9b05688c, 0x1f83d9ab, 0x5be0cd19
    ];
    const words = new Uint32Array(64);
    const rotateRight = (value, count) => (value >>> count) | (value << (32 - count));

    for (let offset = 0; offset < data.length; offset += 64) {
      for (let index = 0; index < 16; index += 1) {
        const byteOffset = offset + index * 4;
        words[index] = (
          (data[byteOffset] << 24) |
          (data[byteOffset + 1] << 16) |
          (data[byteOffset + 2] << 8) |
          data[byteOffset + 3]
        ) >>> 0;
      }
      for (let index = 16; index < 64; index += 1) {
        const first = words[index - 15];
        const second = words[index - 2];
        const sigma0 = rotateRight(first, 7) ^ rotateRight(first, 18) ^ (first >>> 3);
        const sigma1 = rotateRight(second, 17) ^ rotateRight(second, 19) ^ (second >>> 10);
        words[index] = (words[index - 16] + sigma0 + words[index - 7] + sigma1) >>> 0;
      }

      let [a, b, c, d, e, f, g, h] = state;
      for (let index = 0; index < 64; index += 1) {
        const sum1 = rotateRight(e, 6) ^ rotateRight(e, 11) ^ rotateRight(e, 25);
        const choice = (e & f) ^ (~e & g);
        const temporary1 = (h + sum1 + choice + constants[index] + words[index]) >>> 0;
        const sum0 = rotateRight(a, 2) ^ rotateRight(a, 13) ^ rotateRight(a, 22);
        const majority = (a & b) ^ (a & c) ^ (b & c);
        const temporary2 = (sum0 + majority) >>> 0;
        h = g;
        g = f;
        f = e;
        e = (d + temporary1) >>> 0;
        d = c;
        c = b;
        b = a;
        a = (temporary1 + temporary2) >>> 0;
      }
      state[0] = (state[0] + a) >>> 0;
      state[1] = (state[1] + b) >>> 0;
      state[2] = (state[2] + c) >>> 0;
      state[3] = (state[3] + d) >>> 0;
      state[4] = (state[4] + e) >>> 0;
      state[5] = (state[5] + f) >>> 0;
      state[6] = (state[6] + g) >>> 0;
      state[7] = (state[7] + h) >>> 0;
    }

    return state.map(value => value.toString(16).padStart(8, '0')).join('');
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

  function showToolbar(sectionID, annotation) {
    const selector = annotation.target.selector[0];
    const range = selector?.range;
    if (!selector || !range || !selector.quote.trim()) return;
    const rect = range.getBoundingClientRect();
    pendingSelection = { sectionID, annotation, selector };
    toolbar.style.left = `${Math.max(8, rect.x)}px`;
    toolbar.style.top = `${Math.max(8, rect.y - 42)}px`;
    toolbar.hidden = false;
  }

  function removePendingSelection() {
    if (pendingSelection) {
      const { annotation } = pendingSelection;
      annotators.forEach(({ annotator }) => annotator.removeAnnotation(annotation.id));
    }
    pendingSelection = null;
    toolbar.hidden = true;
  }

  function contextScore(text, start, end, note) {
    const prefix = note.prefix || '';
    const suffix = note.suffix || '';
    let score = 0;
    if (prefix && text.slice(Math.max(0, start - prefix.length), start) === prefix) score += prefix.length;
    if (suffix && text.slice(end, end + suffix.length) === suffix) score += suffix.length;
    return score;
  }

  // Recovery order: same rendered text + position/exact, then exact quote plus
  // surrounding context. Returning null leaves the persisted note orphaned
  // rather than painting a potentially wrong span.
  function resolveSelector(note, visibleText, visibleTextHash) {
    const exact = note.exact || note.quote;
    if (!exact) return null;
    const start = Number.isInteger(note.positionStart) ? note.positionStart : note.locationUTF16;
    const end = Number.isInteger(note.positionEnd) ? note.positionEnd : note.locationUTF16 + note.lengthUTF16;
    if (note.visibleTextHash === visibleTextHash &&
        start >= 0 && end > start && visibleText.slice(start, end) === exact) {
      return { quote: exact, start, end };
    }

    const candidates = [];
    let offset = visibleText.indexOf(exact);
    while (offset >= 0) {
      candidates.push({ start: offset, end: offset + exact.length });
      offset = visibleText.indexOf(exact, offset + 1);
    }
    if (!candidates.length) return null;
    candidates.sort((left, right) => contextScore(visibleText, right.start, right.end, note) - contextScore(visibleText, left.start, left.end, note));
    const best = candidates[0];
    const bestScore = contextScore(visibleText, best.start, best.end, note);
    const tie = candidates[1] && contextScore(visibleText, candidates[1].start, candidates[1].end, note) === bestScore;
    return tie ? null : { quote: exact, ...best };
  }

  function noteAnnotation(note, selector) {
    return {
      id: note.id,
      bodies: [],
      target: { selector: [selector] }
    };
  }

  // In macOS WKWebView, the native selection can settle just after pointerup.
  // Recogito normally observes selectionchange before pointerup; if that order
  // is reversed, its debounced selection handler misses the temporary
  // annotation. This fallback still delegates selector generation and storage
  // to Recogito; it only waits for the browser's native selection to settle.
  function recoverWKWebViewSelectionAfterPointerUp(event) {
    if (!currentDocument.allowsAnnotations || event.button !== 0) return;
    window.setTimeout(() => {
      if (pendingSelection) return;
      const selection = window.getSelection();
      if (!selection || selection.isCollapsed || selection.rangeCount !== 1) return;
      const range = selection.getRangeAt(0);
      const target = annotators.find(({ element }) =>
        element.isConnected &&
        element.contains(range.startContainer) &&
        element.contains(range.endContainer)
      );
      if (!target || !range.toString().trim()) return;
      const selector = window.RecogitoJS.rangeToSelector(range, target.element);
      if (!selector?.quote.trim()) return;
      target.annotator.addAnnotation({
        id: crypto.randomUUID(),
        bodies: [],
        target: { selector: [selector] }
      });
    }, 32);
  }

  function makeAnnotator(section, rendered, notes) {
    const visibleText = rendered.textContent || '';
    const visibleTextHash = sha256(visibleText);
    const annotator = window.RecogitoJS.createTextAnnotator(rendered, {
      renderer: 'SPANS',
      annotatingEnabled: currentDocument.allowsAnnotations,
      selectionMode: 'all',
      style: { fill: 'rgba(255, 223, 88, .62)', fillOpacity: 0.62 }
    });
    const resolved = notes
      .filter(note => !note.sourceHash || note.sourceHash === section.sourceHash)
      .map(note => {
        const selector = resolveSelector(note, visibleText, visibleTextHash);
        return selector ? noteAnnotation(note, selector) : null;
      })
      .filter(Boolean);
    annotator.setAnnotations(resolved);
    annotator.on('createAnnotation', annotation => {
      recordDiagnostic('createAnnotation');
      showToolbar(section.id, annotation);
    });
    annotator.on('clickAnnotation', annotation => {
      const selected = Array.isArray(annotation) ? annotation[0] : annotation;
      if (selected?.id) post('editHighlight', { noteID: selected.id });
    });
    annotators.push({ sectionID: section.id, element: rendered, annotator });
  }

  async function render(payload) {
    annotators.forEach(({ annotator }) => annotator.destroy());
    annotators = [];
    currentDocument = payload;
    pendingSelection = null;
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
      rendered.style.fontSize = `${payload.bodyFontSize || 16}px`;
      upgradeTaskItems(rendered);
      element.appendChild(rendered);
      documentRoot.appendChild(element);
      try {
        makeAnnotator(section, rendered, (payload.notes || []).filter(note => note.sectionID === section.id));
      } catch (error) {
        console.error('Recogito annotator initialization failed', error);
      }
    }
  }

  function performToolbarAction(event) {
    const button = event.target.closest('button[data-action]');
    const action = button?.dataset.action;
    if (!action || !pendingSelection) return;
    event.preventDefault();
    event.stopPropagation();
    const { sectionID, selector } = pendingSelection;
    const section = document.querySelector(`[data-section-id="${CSS.escape(sectionID)}"] > div`);
    const visibleText = section?.textContent || '';
    const start = selector.start;
    const end = selector.end;
    post(action, {
      sectionID,
      locationUTF16: start,
      lengthUTF16: end - start,
      quote: selector.quote,
      visibleText,
      prefix: visibleText.slice(Math.max(0, start - 64), start),
      suffix: visibleText.slice(end, end + 64)
    });
    window.getSelection()?.removeAllRanges();
    removePendingSelection();
  }

  document.addEventListener('mousedown', event => {
    if (!event.target.closest('.selection-toolbar') && !event.target.closest('.r6o-annotation')) {
      removePendingSelection();
    }
  });
  document.addEventListener('pointerdown', () => recordDiagnostic('pointerdown'));
  document.addEventListener('pointerup', event => {
    recordDiagnostic('pointerup');
    recoverWKWebViewSelectionAfterPointerUp(event);
  });
  document.addEventListener('selectionchange', () => recordDiagnostic('selectionchange'));
  toolbar.addEventListener('pointerdown', event => event.stopPropagation());
  toolbar.addEventListener('click', performToolbarAction);
  document.addEventListener('click', event => {
    const link = event.target.closest('a');
    if (link?.href) {
      event.preventDefault();
      post('openLink', { href: link.href });
    }
  });

  window.obsidianReader = {
    load(encoded) { return render(decodeBase64JSON(encoded)); },
    scrollToSection(id) { document.querySelector(`[data-section-id="${CSS.escape(id)}"]`)?.scrollIntoView({ block: 'start' }); },
    clearSelection() { window.getSelection()?.removeAllRanges(); removePendingSelection(); }
  };
})();
