// StateMachine.js — generic finite state machine.
// Reused by the movement controller (Walk/Sprint/Jump/Dash) and could drive
// enemy AI or combat states. Each state is a plain object with optional
// enter(ctx), update(ctx, dt), exit(ctx) hooks plus a `transitions` guard map.

export class State {
  constructor(name, { enter, update, exit, canEnter } = {}) {
    this.name = name;
    this._enter = enter;
    this._update = update;
    this._exit = exit;
    this._canEnter = canEnter;
  }

  canEnter(ctx, from) {
    return this._canEnter ? this._canEnter(ctx, from) : true;
  }

  enter(ctx, from) {
    if (this._enter) this._enter(ctx, from);
  }

  update(ctx, dt) {
    if (this._update) this._update(ctx, dt);
  }

  exit(ctx, to) {
    if (this._exit) this._exit(ctx, to);
  }
}

export class StateMachine {
  constructor(ctx) {
    this.ctx = ctx;
    this.states = new Map();
    this.current = null;
    this.previous = null;
    this.timeInState = 0;
  }

  add(state) {
    this.states.set(state.name, state);
    return this;
  }

  has(name) {
    return this.states.has(name);
  }

  // Returns true if the transition succeeded.
  change(name, force = false) {
    const next = this.states.get(name);
    if (!next) {
      console.warn(`[StateMachine] unknown state "${name}"`);
      return false;
    }
    if (this.current && this.current.name === name) return false;
    if (!force && !next.canEnter(this.ctx, this.current?.name ?? null)) return false;

    const from = this.current;
    if (from) from.exit(this.ctx, name);
    this.previous = from ? from.name : null;
    this.current = next;
    this.timeInState = 0;
    next.enter(this.ctx, this.previous);
    return true;
  }

  update(dt) {
    if (!this.current) return;
    this.timeInState += dt;
    this.current.update(this.ctx, dt);
  }

  is(name) {
    return this.current?.name === name;
  }

  get name() {
    return this.current?.name ?? null;
  }
}

export default StateMachine;
