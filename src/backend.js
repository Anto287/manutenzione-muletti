// Supabase REST adapter. Never use a service_role / secret key here.
export class LiftCareBackend {
  constructor({url, publishableKey, fetch: fetcher = globalThis.fetch}) {
    const parsed = new URL(url);
    if (parsed.protocol !== 'https:' && parsed.hostname !== 'localhost' && parsed.hostname !== '127.0.0.1') throw Error('Usa HTTPS per il backend.');
    if (!publishableKey) throw Error('Chiave pubblica Supabase mancante.');
    this.url = parsed.origin;
    this.key = publishableKey;
    this.fetch = (...args) => fetcher.call(globalThis, ...args);
    this.session = null; // Caller decides session persistence. No silent localStorage writes.
  }
  async request(path, {method = 'GET', body, headers = {}, authenticated = true} = {}) {
    if (authenticated && !this.session?.access_token) throw Error('Accedi prima di usare il backend.');
    const response = await this.fetch(this.url + path, {
      method,
      signal: AbortSignal.timeout(20000),
      headers: {apikey: this.key, ...(this.session?.access_token ? {Authorization: `Bearer ${this.session.access_token}`} : {}),
        ...(body === undefined ? {} : {'Content-Type': 'application/json'}), ...headers},
      ...(body === undefined ? {} : {body: body instanceof Blob ? body : JSON.stringify(body)})
    });
    const raw = await response.text();
    let value;
    try { value = raw ? JSON.parse(raw) : null; } catch { value = raw; }
    if (!response.ok) {
      const error = Error(value?.message || value?.msg || value?.error_description || `Backend: errore ${response.status}`);
      error.status = response.status;
      throw error;
    }
    return value;
  }
  async signIn(email, password) {
    const session = await this.request('/auth/v1/token?grant_type=password', {method:'POST', body:{email,password}, authenticated:false});
    this.session = {...session,expires_at:Math.floor(Date.now()/1000)+session.expires_in};
    return session.user;
  }
  async refreshSession() {
    if (!this.session?.refresh_token) throw Error('Accedi nuovamente.');
    this.session = await this.request('/auth/v1/token?grant_type=refresh_token', {
      method:'POST',body:{refresh_token:this.session.refresh_token},authenticated:false
    });
    this.session.expires_at=Math.floor(Date.now()/1000)+this.session.expires_in;
    return this.session.user;
  }
  async signOut() {
    try { if (this.session) await this.request('/auth/v1/logout', {method:'POST'}); }
    finally { this.session = null; }
  }
  async list(table, {offset=0, limit=100} = {}) {
    if (!['machines','maintenance_plans','service_records'].includes(table)) throw Error('Risorsa non valida.');
    if (!Number.isInteger(offset) || offset<0 || !Number.isInteger(limit) || limit<1 || limit>1000) throw Error('Paginazione non valida.');
    return this.request(`/rest/v1/${table}?select=*&order=id&offset=${offset}&limit=${limit}`);
  }
  async write(table, values, id) {
    if (!['machines','maintenance_plans'].includes(table)) throw Error('Risorsa non modificabile.');
    if ('owner_id' in values || 'created_at' in values || (id && 'id' in values)) throw Error('Campi di sistema non modificabili.');
    const rows = await this.request(`/rest/v1/${table}${id ? `?id=eq.${encodeURIComponent(id)}` : ''}`, {
      method:id?'PATCH':'POST',body:values,headers:{Prefer:'return=representation'}
    });
    if (!rows?.length) throw Error('Risorsa non disponibile.');
    return rows[0];
  }
  saveMachine(values, id) { return this.write('machines', values, id); }
  savePlan(values, id) { return this.write('maintenance_plans', values, id); }
  async remove(table, id) {
    if (!['machines','maintenance_plans'].includes(table)) throw Error('Risorsa non eliminabile.');
    return this.request(`/rest/v1/${table}?id=eq.${encodeURIComponent(id)}`, {method:'DELETE',headers:{Prefer:'return=representation'}});
  }
  async recordService({machineId, planIds, date, reading, cost=0, technician='', notes='', items=[]}) {
    const result=await this.request('/rest/v1/rpc/'+(items.length?'record_completed_work':'record_service'), {method:'POST',body:{
      ...(items.length?{p_items:items}:{}),
      p_machine_id:machineId,p_plan_ids:planIds,p_date:date,p_reading:reading,p_cost:cost,p_technician:technician,p_notes:notes
    }});
    const row=Array.isArray(result)?result[0]:result;
    if(!row?.id)throw Error('Risposta intervento non valida: aggiorna l’archivio prima di riprovare.');
    return row;
  }
  photoPath(serviceId, slot, extension) {
    if (!this.session?.user?.id) throw Error('Accesso richiesto.');
    if (!/^[a-zA-Z0-9_-]+$/.test(serviceId) || !Number.isInteger(slot) || slot<1 || slot>6 || !['jpg','png','webp'].includes(extension)) throw Error('Allegato non valido.');
    return `${this.session.user.id}/${serviceId}/${slot}.${extension}`;
  }
  async uploadPhoto(serviceId, slot, blob) {
    const extension = {'image/jpeg':'jpg','image/png':'png','image/webp':'webp'}[blob.type];
    if (!extension || blob.size>160000 || blob.size===0) throw Error('Foto non valida: massimo 160 KB, JPEG, PNG o WebP.');
    const path = this.photoPath(serviceId, slot, extension);
    await this.request(`/storage/v1/object/liftcare-photos/${path}`, {method:'POST',body:blob,headers:{'Content-Type':blob.type,'x-upsert':'false'}});
    return path;
  }
  async listPhotos(serviceId) {
    const prefix = this.photoPath(serviceId,1,'jpg').split('/').slice(0,2).join('/');
    return this.request('/storage/v1/object/list/liftcare-photos', {method:'POST',body:{prefix,limit:6,offset:0,sortBy:{column:'name',order:'asc'}}});
  }
  async signedPhotoUrl(serviceId, slot, extension='jpg') {
    const result = await this.request(`/storage/v1/object/sign/liftcare-photos/${this.photoPath(serviceId,slot,extension)}`, {method:'POST',body:{expiresIn:300}});
    return new URL(`/storage/v1${result.signedURL}`,this.url).href;
  }
  deletePhoto(serviceId,slot,extension='jpg') {
    return this.request('/storage/v1/object/liftcare-photos', {method:'DELETE',body:{prefixes:[this.photoPath(serviceId,slot,extension)]}});
  }
}
