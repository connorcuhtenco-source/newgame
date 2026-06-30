// Input.js — centralized input manager (singleton).
// Tracks held keys/mouse buttons and exposes "pressed this frame" edges plus
// timed-hold helpers used by the parry window. Pointer-lock aware: it reports
// raw mouse-delta for look controls and clears state on focus loss.

import Events from './EventBus.js';

class InputManager {
  constructor() {
    this.keys = new Set();          // currently held key codes
    this.pressedThisFrame = new Set();
    this.releasedThisFrame = new Set();
    this.mouse = { left: false, right: false, dx: 0, dy: 0 };
    this.mousePressed = { left: false, right: false };
    this.mouseReleased = { left: false, right: false };
    this.holdStart = new Map();     // code -> timestamp held since
    this.enabled = false;
    this._bound = false;
  }

  attach(domElement) {
    if (this._bound) return;
    this._bound = true;
    this.dom = domElement || document.body;

    window.addEventListener('keydown', this._onKeyDown);
    window.addEventListener('keyup', this._onKeyUp);
    window.addEventListener('mousedown', this._onMouseDown);
    window.addEventListener('mouseup', this._onMouseUp);
    window.addEventListener('mousemove', this._onMouseMove);
    window.addEventListener('blur', this._onBlur);
    // Prevent the context menu so right-click can be used for heavy attacks.
    window.addEventListener('contextmenu', (e) => {
      if (this.enabled) e.preventDefault();
    });
  }

  setEnabled(v) {
    this.enabled = v;
    if (!v) this._clear();
  }

  _clear() {
    this.keys.clear();
    this.holdStart.clear();
    this.mouse.left = this.mouse.right = false;
  }

  _onBlur = () => this._clear();

  _onKeyDown = (e) => {
    if (!this.enabled) return;
    const code = e.code;
    if (!this.keys.has(code)) {
      this.keys.add(code);
      this.pressedThisFrame.add(code);
      this.holdStart.set(code, performance.now());
    }
    // Stop the page from scrolling on space/arrows while playing.
    if (['Space', 'ArrowUp', 'ArrowDown', 'ArrowLeft', 'ArrowRight'].includes(code)) {
      e.preventDefault();
    }
  };

  _onKeyUp = (e) => {
    const code = e.code;
    this.keys.delete(code);
    this.releasedThisFrame.add(code);
    const start = this.holdStart.get(code);
    this.holdStart.delete(code);
    if (start != null) {
      // Broadcast the hold duration so systems (parry) can react on release.
      Events.emit('input:keyup', { code, heldMs: performance.now() - start });
    }
  };

  _onMouseDown = (e) => {
    if (!this.enabled) return;
    if (e.button === 0) { this.mouse.left = true; this.mousePressed.left = true; }
    if (e.button === 2) { this.mouse.right = true; this.mousePressed.right = true; }
  };

  _onMouseUp = (e) => {
    if (e.button === 0) { this.mouse.left = false; this.mouseReleased.left = true; }
    if (e.button === 2) { this.mouse.right = false; this.mouseReleased.right = true; }
  };

  _onMouseMove = (e) => {
    if (!this.enabled) return;
    this.mouse.dx += e.movementX || 0;
    this.mouse.dy += e.movementY || 0;
  };

  isDown(code) { return this.keys.has(code); }

  pressed(code) { return this.pressedThisFrame.has(code); }

  released(code) { return this.releasedThisFrame.has(code); }

  // How long (ms) a key has been held, or 0 if not held.
  heldMs(code) {
    const start = this.holdStart.get(code);
    return start == null ? 0 : performance.now() - start;
  }

  // Any of WASD currently held — used to validate a directional dash.
  moveVector() {
    let x = 0, z = 0;
    if (this.isDown('KeyW')) z -= 1;
    if (this.isDown('KeyS')) z += 1;
    if (this.isDown('KeyA')) x -= 1;
    if (this.isDown('KeyD')) x += 1;
    return { x, z };
  }

  // Call once at the END of each frame to clear per-frame edges + mouse delta.
  endFrame() {
    this.pressedThisFrame.clear();
    this.releasedThisFrame.clear();
    this.mousePressed.left = this.mousePressed.right = false;
    this.mouseReleased.left = this.mouseReleased.right = false;
    this.mouse.dx = 0;
    this.mouse.dy = 0;
  }
}

export const Input = new InputManager();
export default Input;
