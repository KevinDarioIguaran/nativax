/// In-memory IndexedDB: databases live for the lifetime of the runtime.
/// Supports versioned open/upgrade, object stores with keyPath and
/// autoIncrement, indexes (including unique and multiEntry), key ranges,
/// cursors and transactions with complete/abort events.
const String webIndexedDb = r'''
// ============================================================================
// IndexedDB
// ============================================================================
const idbDatabases = new Map(); // name -> { version, stores: Map<name, store> }
const compareKeys = (a, b) => {
  const rank = (k) => (typeof k === 'number' ? 1 : k instanceof Date ? 2 : typeof k === 'string' ? 3 : k instanceof ArrayBuffer || ArrayBuffer.isView(k) ? 4 : Array.isArray(k) ? 5 : 0);
  const ra = rank(a), rb = rank(b);
  if (ra === 0 || rb === 0) throw new DOMException('The parameter is not a valid key.', 'DataError');
  if (ra !== rb) return ra < rb ? -1 : 1;
  if (ra === 5) {
    for (let i = 0; i < Math.min(a.length, b.length); i++) { const c = compareKeys(a[i], b[i]); if (c) return c; }
    return a.length === b.length ? 0 : (a.length < b.length ? -1 : 1);
  }
  if (ra === 4) { const x = toBytes(a), y = toBytes(b); for (let i = 0; i < Math.min(x.length, y.length); i++) if (x[i] !== y[i]) return x[i] < y[i] ? -1 : 1; return x.length - y.length; }
  const x = ra === 2 ? a.getTime() : a, y = rb === 2 ? b.getTime() : b;
  return x < y ? -1 : x > y ? 1 : 0;
};
const validKey = (k) => { try { compareKeys(k, k); return !(typeof k === 'number' && Number.isNaN(k)); } catch (e) { return false; } };
const keyFromPath = (value, path) => {
  if (Array.isArray(path)) return path.map((p) => keyFromPath(value, p));
  if (path === '') return value;
  let v = value;
  for (const part of String(path).split('.')) { if (v === null || typeof v !== 'object' || !(part in v)) return undefined; v = v[part]; }
  return v;
};
const setPath = (value, path, key) => {
  const parts = String(path).split('.');
  let v = value;
  for (let i = 0; i < parts.length - 1; i++) { if (!(parts[i] in v)) v[parts[i]] = {}; v = v[parts[i]]; }
  v[parts[parts.length - 1]] = key;
};
class IDBKeyRange {
  constructor(lower, upper, lowerOpen = false, upperOpen = false) { Object.assign(this, { lower, upper, lowerOpen, upperOpen }); }
  includes(k) {
    if (this.lower !== undefined) { const c = compareKeys(k, this.lower); if (c < 0 || (c === 0 && this.lowerOpen)) return false; }
    if (this.upper !== undefined) { const c = compareKeys(k, this.upper); if (c > 0 || (c === 0 && this.upperOpen)) return false; }
    return true;
  }
  static only(k) { if (!validKey(k)) throw new DOMException('The parameter is not a valid key.', 'DataError'); return new IDBKeyRange(k, k); }
  static lowerBound(k, open = false) { return new IDBKeyRange(k, undefined, open, true); }
  static upperBound(k, open = false) { return new IDBKeyRange(undefined, k, true, open); }
  static bound(a, b, ao = false, bo = false) { if (compareKeys(a, b) > 0) throw new DOMException('The lower key is greater than the upper key.', 'DataError'); return new IDBKeyRange(a, b, ao, bo); }
}
const asRange = (q) => (q === undefined || q === null ? null : q instanceof IDBKeyRange ? q : IDBKeyRange.only(q));
class IDBRequest extends EventTarget {
  constructor(source, tx) { super(); Object.assign(this, { result: undefined, error: null, source, transaction: tx || null, readyState: 'pending' }); }
}
class IDBOpenDBRequest extends IDBRequest {}
class IDBVersionChangeEvent extends Event {
  constructor(type, init = {}) { super(type, init); hidden(this, 'oldVersion', init.oldVersion ?? 0); hidden(this, 'newVersion', init.newVersion ?? null); }
}
const succeed = (req, result) => {
  req.readyState = 'done';
  req.result = result;
  req.dispatchEvent(new Event('success'));
};
const fail = (req, error) => {
  req.readyState = 'done';
  req.error = error;
  const ok = req.dispatchEvent(new Event('error', { bubbles: true, cancelable: true }));
  const tx = req.transaction;
  if (tx && ok) tx.abort(error);
};
class IDBTransaction extends EventTarget {
  constructor(db, names, mode) {
    super();
    Object.assign(this, { db, mode, objectStoreNames: names.slice(), error: null, durability: 'default' });
    hidden(this, '_s', { pending: 0, done: false, aborted: false, snapshot: null, active: true });
    if (mode !== 'readonly') hidden(this, '_backup', new Map(names.map((n) => [n, db._data.stores.get(n) && cloneStore(db._data.stores.get(n))])));
    queueMicrotask(() => this._maybeFinish());
  }
  objectStore(name) {
    if (!this.objectStoreNames.includes(name)) throw new DOMException(`No objectStore named ${name} in this transaction`, 'NotFoundError');
    if (this._s.done) throw new DOMException('The transaction has finished.', 'InvalidStateError');
    return new IDBObjectStore(this, name);
  }
  _request(source, fn) {
    if (this._s.done || this._s.aborted) throw new DOMException('The transaction has finished.', 'TransactionInactiveError');
    const req = new IDBRequest(source, this);
    this._s.pending++;
    setTimeout(() => {
      this._s.pending--;
      if (this._s.aborted) return;
      try { succeed(req, fn()); } catch (e) { fail(req, e instanceof DOMException ? e : new DOMException(String(e && e.message || e), 'DataError')); }
      this._maybeFinish();
    }, 0);
    return req;
  }
  _maybeFinish() {
    setTimeout(() => {
      if (this._s.done || this._s.aborted || this._s.pending > 0) return;
      this._s.done = true;
      this.dispatchEvent(new Event('complete'));
    }, 0);
  }
  abort(error) {
    if (this._s.done || this._s.aborted) return;
    this._s.aborted = true;
    this.error = error || null;
    if (this._backup) for (const [n, s] of this._backup) { if (s) this.db._data.stores.set(n, s); else this.db._data.stores.delete(n); }
    setTimeout(() => this.dispatchEvent(new Event('abort', { bubbles: true })), 0);
  }
  commit() {}
}
const cloneStore = (s) => ({ keyPath: s.keyPath, autoIncrement: s.autoIncrement, next: s.next, records: s.records.map((r) => ({ key: r.key, value: structuredClone(r.value) })), indexes: new Map([...s.indexes].map(([k, v]) => [k, Object.assign({}, v)])) });
const storeData = (tx, name) => {
  const s = tx.db._data.stores.get(name);
  if (!s) throw new DOMException('The object store was deleted.', 'InvalidStateError');
  return s;
};
const findIndex = (records, key) => {
  let lo = 0, hi = records.length;
  while (lo < hi) { const mid = (lo + hi) >> 1; if (compareKeys(records[mid].key, key) < 0) lo = mid + 1; else hi = mid; }
  return lo;
};
const indexKeys = (idx, value) => {
  const k = keyFromPath(value, idx.keyPath);
  if (k === undefined) return [];
  if (idx.multiEntry && Array.isArray(k)) return [...new Set(k.filter(validKey))];
  return validKey(k) ? [k] : [];
};
class IDBObjectStore {
  constructor(tx, name) {
    const s = storeData(tx, name);
    Object.assign(this, { transaction: tx, name, keyPath: s.keyPath, autoIncrement: s.autoIncrement });
  }
  get indexNames() { return [...storeData(this.transaction, this.name).indexes.keys()].sort(); }
  _write(value, key, overwrite) {
    const tx = this.transaction;
    if (tx.mode === 'readonly') throw new DOMException('The transaction is read-only.', 'ReadOnlyError');
    const s = storeData(tx, this.name);
    const v = structuredClone(value);
    let k = key;
    if (s.keyPath !== null) {
      if (key !== undefined) throw new DOMException('The object store uses in-line keys and the key parameter was provided.', 'DataError');
      k = keyFromPath(v, s.keyPath);
      if (k === undefined && s.autoIncrement) { k = s.next++; setPath(v, s.keyPath, k); }
    } else if (k === undefined && s.autoIncrement) k = s.next++;
    if (!validKey(k)) throw new DOMException('Evaluating the object store\'s key path did not yield a value.', 'DataError');
    return tx._request(this, () => {
      const st = storeData(tx, this.name);
      if (typeof k === 'number' && st.autoIncrement && k >= st.next) st.next = Math.floor(k) + 1;
      const i = findIndex(st.records, k);
      const exists = i < st.records.length && compareKeys(st.records[i].key, k) === 0;
      if (exists && !overwrite) throw new DOMException('Key already exists in the object store.', 'ConstraintError');
      for (const idx of st.indexes.values()) {
        if (!idx.unique) continue;
        for (const ik of indexKeys(idx, v)) {
          if (st.records.some((r) => compareKeys(r.key, k) !== 0 && indexKeys(idx, r.value).some((x) => compareKeys(x, ik) === 0))) {
            throw new DOMException('Unable to add key to index: at least one key does not satisfy the uniqueness requirements.', 'ConstraintError');
          }
        }
      }
      if (exists) st.records[i].value = v; else st.records.splice(i, 0, { key: k, value: v });
      return k;
    });
  }
  put(value, key) { return this._write(value, key, true); }
  add(value, key) { return this._write(value, key, false); }
  _select(query, count) {
    const s = storeData(this.transaction, this.name);
    const range = asRange(query);
    const out = [];
    for (const r of s.records) { if (!range || range.includes(r.key)) { out.push(r); if (count && out.length >= count) break; } }
    return out;
  }
  get(query) { return this.transaction._request(this, () => { const r = this._select(query, 1)[0]; return r ? structuredClone(r.value) : undefined; }); }
  getKey(query) { return this.transaction._request(this, () => { const r = this._select(query, 1)[0]; return r ? r.key : undefined; }); }
  getAll(query, count) { return this.transaction._request(this, () => this._select(query, count).map((r) => structuredClone(r.value))); }
  getAllKeys(query, count) { return this.transaction._request(this, () => this._select(query, count).map((r) => r.key)); }
  count(query) { return this.transaction._request(this, () => this._select(query).length); }
  delete(query) {
    if (this.transaction.mode === 'readonly') throw new DOMException('The transaction is read-only.', 'ReadOnlyError');
    return this.transaction._request(this, () => {
      const s = storeData(this.transaction, this.name);
      const range = asRange(query);
      s.records = s.records.filter((r) => !range.includes(r.key));
      return undefined;
    });
  }
  clear() {
    if (this.transaction.mode === 'readonly') throw new DOMException('The transaction is read-only.', 'ReadOnlyError');
    return this.transaction._request(this, () => { storeData(this.transaction, this.name).records = []; return undefined; });
  }
  openCursor(query, direction = 'next') { return openCursor(this, () => this._select(query).map((r) => ({ key: r.key, primaryKey: r.key, value: r.value })), direction, true); }
  openKeyCursor(query, direction = 'next') { return openCursor(this, () => this._select(query).map((r) => ({ key: r.key, primaryKey: r.key, value: r.value })), direction, false); }
  createIndex(name, keyPath, options = {}) {
    if (!this.transaction._upgrade) throw new DOMException('The database is not running a version change transaction.', 'InvalidStateError');
    const s = storeData(this.transaction, this.name);
    if (s.indexes.has(name)) throw new DOMException(`An index named '${name}' already exists.`, 'ConstraintError');
    s.indexes.set(name, { name, keyPath, unique: !!options.unique, multiEntry: !!options.multiEntry });
    return new IDBIndex(this, name);
  }
  deleteIndex(name) { storeData(this.transaction, this.name).indexes.delete(name); }
  index(name) {
    if (!storeData(this.transaction, this.name).indexes.has(name)) throw new DOMException(`The specified index '${name}' was not found.`, 'NotFoundError');
    return new IDBIndex(this, name);
  }
}
class IDBIndex {
  constructor(store, name) {
    const idx = storeData(store.transaction, store.name).indexes.get(name);
    Object.assign(this, { objectStore: store, name, keyPath: idx.keyPath, unique: idx.unique, multiEntry: idx.multiEntry });
  }
  _entries(query) {
    const s = storeData(this.objectStore.transaction, this.objectStore.name);
    const idx = s.indexes.get(this.name);
    const range = asRange(query);
    const out = [];
    for (const r of s.records) for (const k of indexKeys(idx, r.value)) if (!range || range.includes(k)) out.push({ key: k, primaryKey: r.key, value: r.value });
    out.sort((a, b) => compareKeys(a.key, b.key) || compareKeys(a.primaryKey, b.primaryKey));
    return out;
  }
  _req(fn) { return this.objectStore.transaction._request(this, fn); }
  get(q) { return this._req(() => { const e = this._entries(q)[0]; return e ? structuredClone(e.value) : undefined; }); }
  getKey(q) { return this._req(() => { const e = this._entries(q)[0]; return e ? e.primaryKey : undefined; }); }
  getAll(q, count) { return this._req(() => this._entries(q).slice(0, count || undefined).map((e) => structuredClone(e.value))); }
  getAllKeys(q, count) { return this._req(() => this._entries(q).slice(0, count || undefined).map((e) => e.primaryKey)); }
  count(q) { return this._req(() => this._entries(q).length); }
  openCursor(q, direction = 'next') { return openCursor(this, () => this._entries(q), direction, true); }
  openKeyCursor(q, direction = 'next') { return openCursor(this, () => this._entries(q), direction, false); }
}
class IDBCursor {
  constructor(source, req, entries, direction, withValue) {
    hidden(this, '_c', { entries, pos: -1, req, withValue });
    Object.assign(this, { source, direction, request: req });
  }
  get key() { const e = this._c.entries[this._c.pos]; return e ? e.key : undefined; }
  get primaryKey() { const e = this._c.entries[this._c.pos]; return e ? e.primaryKey : undefined; }
  _advance(n) {
    const c = this._c;
    const tx = (this.source.transaction || this.source.objectStore.transaction);
    tx._s.pending++;
    setTimeout(() => {
      tx._s.pending--;
      c.pos += n;
      succeed(c.req, c.pos < c.entries.length ? this : null);
      tx._maybeFinish();
    }, 0);
  }
  continue(key) {
    if (key === undefined) { this._advance(1); return; }
    const c = this._c;
    let n = 1;
    while (c.pos + n < c.entries.length && compareKeys(c.entries[c.pos + n].key, key) * (this.direction.startsWith('prev') ? -1 : 1) < 0) n++;
    this._advance(n);
  }
  continuePrimaryKey(key, primaryKey) { this.continue(key); }
  advance(n) { if (n <= 0) throw new TypeError('count must be positive'); this._advance(n); }
  update(value) {
    const store = this.source instanceof IDBIndex ? this.source.objectStore : this.source;
    return store.keyPath !== null ? store.put(value) : store.put(value, this.primaryKey);
  }
  delete() { const store = this.source instanceof IDBIndex ? this.source.objectStore : this.source; return store.delete(this.primaryKey); }
}
class IDBCursorWithValue extends IDBCursor {
  get value() { const e = this._c.entries[this._c.pos]; return e ? structuredClone(e.value) : undefined; }
}
const openCursor = (source, select, direction, withValue) => {
  const tx = source.transaction || source.objectStore.transaction;
  const req = new IDBRequest(source, tx);
  tx._s.pending++;
  setTimeout(() => {
    tx._s.pending--;
    let entries = select();
    if (direction.startsWith('prev')) entries = entries.reverse();
    if (direction.endsWith('unique')) entries = entries.filter((e, i) => i === 0 || compareKeys(e.key, entries[i - 1].key) !== 0);
    const cursor = new (withValue ? IDBCursorWithValue : IDBCursor)(source, req, entries, direction, withValue);
    cursor._c.pos = 0;
    succeed(req, entries.length ? cursor : null);
    tx._maybeFinish();
  }, 0);
  return req;
};
class IDBDatabase extends EventTarget {
  constructor(name, data) { super(); hidden(this, '_data', data); hidden(this, '_closed', { v: false }); this.name = name; }
  get version() { return this._data.version; }
  get objectStoreNames() { const names = [...this._data.stores.keys()].sort(); names.contains = (n) => names.includes(n); names.item = (i) => names[i] ?? null; return names; }
  createObjectStore(name, options = {}) {
    if (!this._upgradeTx) throw new DOMException('The database is not running a version change transaction.', 'InvalidStateError');
    if (this._data.stores.has(name)) throw new DOMException(`An object store named '${name}' already exists.`, 'ConstraintError');
    const keyPath = options.keyPath === undefined ? null : options.keyPath;
    if (options.autoIncrement && (keyPath === '' || Array.isArray(keyPath))) throw new DOMException('autoIncrement requires a non-empty key path', 'InvalidAccessError');
    this._data.stores.set(name, { keyPath, autoIncrement: !!options.autoIncrement, next: 1, records: [], indexes: new Map() });
    this._upgradeTx.objectStoreNames.push(name);
    return this._upgradeTx.objectStore(name);
  }
  deleteObjectStore(name) {
    if (!this._upgradeTx) throw new DOMException('The database is not running a version change transaction.', 'InvalidStateError');
    if (!this._data.stores.delete(name)) throw new DOMException(`The object store '${name}' was not found.`, 'NotFoundError');
  }
  transaction(names, mode = 'readonly') {
    if (this._closed.v) throw new DOMException('The database connection is closing.', 'InvalidStateError');
    const list = Array.isArray(names) ? names.map(String) : [String(names)];
    for (const n of list) if (!this._data.stores.has(n)) throw new DOMException(`One of the specified object stores '${n}' was not found.`, 'NotFoundError');
    if (!['readonly', 'readwrite'].includes(mode)) throw new TypeError(`The provided value '${mode}' is not a valid enum value of type IDBTransactionMode.`);
    return new IDBTransaction(this, list, mode);
  }
  close() { this._closed.v = true; }
}
class IDBFactory {
  open(name, version) {
    name = String(name);
    if (version !== undefined && (!Number.isInteger(version) || version < 1)) throw new TypeError("Failed to execute 'open' on 'IDBFactory': The version provided must not be 0.");
    const req = new IDBOpenDBRequest(null, null);
    setTimeout(() => {
      let data = idbDatabases.get(name);
      const oldVersion = data ? data.version : 0;
      const newVersion = version === undefined ? Math.max(oldVersion, 1) : version;
      if (data && newVersion < oldVersion) {
        req.readyState = 'done';
        req.error = new DOMException(`The requested version (${newVersion}) is less than the existing version (${oldVersion}).`, 'VersionError');
        req.dispatchEvent(new Event('error', { cancelable: true }));
        return;
      }
      if (!data) { data = { version: 0, stores: new Map() }; idbDatabases.set(name, data); }
      const db = new IDBDatabase(name, data);
      if (newVersion > oldVersion) {
        data.version = newVersion;
        const tx = new IDBTransaction(db, [...data.stores.keys()], 'versionchange');
        tx._upgrade = true;
        db._upgradeTx = tx;
        req.result = db;
        req.transaction = tx;
        req.readyState = 'done';
        req.dispatchEvent(new IDBVersionChangeEvent('upgradeneeded', { oldVersion, newVersion }));
        tx.addEventListener('complete', () => {
          db._upgradeTx = null;
          req.transaction = null;
          succeed(req, db);
        });
        tx.addEventListener('abort', () => {
          db._upgradeTx = null;
          data.version = oldVersion;
          if (oldVersion === 0) idbDatabases.delete(name);
          req.error = new DOMException('The version change transaction was aborted.', 'AbortError');
          req.dispatchEvent(new Event('error'));
        });
        return;
      }
      succeed(req, db);
    }, 0);
    return req;
  }
  deleteDatabase(name) {
    const req = new IDBOpenDBRequest(null, null);
    setTimeout(() => {
      const data = idbDatabases.get(String(name));
      idbDatabases.delete(String(name));
      req.readyState = 'done';
      req.result = undefined;
      req.dispatchEvent(new IDBVersionChangeEvent('success', { oldVersion: data ? data.version : 0, newVersion: null }));
    }, 0);
    return req;
  }
  databases() { return Promise.resolve([...idbDatabases].map(([name, d]) => ({ name, version: d.version }))); }
  cmp(a, b) { return compareKeys(a, b); }
}
const indexedDB = new IDBFactory();
''';
