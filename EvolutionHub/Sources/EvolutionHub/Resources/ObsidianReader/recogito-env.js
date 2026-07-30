// Recogito's UMD build reads the Node-style global name `process`. Keep the
// compatibility shim external: the reader CSP intentionally disallows inline
// scripts, but permits same-bundle scripts.
window.process = window.process || {};
window.process.env = window.process.env || {};
window.process.env.NODE_ENV = window.process.env.NODE_ENV || 'production';
