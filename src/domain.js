export const today = () => {
  const d = new Date();
  return `${d.getFullYear()}-${String(d.getMonth() + 1).padStart(2, '0')}-${String(d.getDate()).padStart(2, '0')}`;
};
export const MAX_PHOTOS = 6;
export const MAX_PHOTO_BYTES = 160000;
export function validPhotos(photos) {
  return photos === undefined || (Array.isArray(photos) && photos.length <= MAX_PHOTOS && photos.every(p => p && typeof p.name === 'string' && p.name.length <= 200 && typeof p.dataUrl === 'string' && p.dataUrl.length <= Math.ceil(MAX_PHOTO_BYTES / 3) * 4 + 40 && /^data:image\/(jpeg|png|webp);base64,[A-Za-z0-9+/]+={0,2}$/.test(p.dataUrl)));
}
export const vehicleTypes = { forklift: 'Muletto', car: 'Auto', tractor: 'Trattore' };
export const unitLabel = v => v.unit === 'km' ? 'km' : 'h';
export const counterLabel = v => v.unit === 'km' ? 'Chilometri' : 'Ore di lavoro';
const str = x => typeof x === 'string';
const identifier = x => str(x) && /^[a-zA-Z0-9_-]+$/.test(x);
const num = x => Number.isFinite(x) && x >= 0;
const validDate = x => str(x) && /^\d{4}-\d{2}-\d{2}$/.test(x) && Number.isFinite(Date.parse(x)) && new Date(x).toISOString().slice(0, 10) === x;
export function addMonths(date, n) {
  const [y, m, d] = date.split('-').map(Number);
  const target = new Date(y, m - 1 + n, 1);
  const last = new Date(target.getFullYear(), target.getMonth() + 1, 0).getDate();
  return `${target.getFullYear()}-${String(target.getMonth() + 1).padStart(2, '0')}-${String(Math.min(d, last)).padStart(2, '0')}`;
}
export function due(task, vehicle, date = today()) {
  const reading = task.interval ? task.lastReading + task.interval : null;
  const day = task.months ? addMonths(task.lastDate, task.months) : null;
  const remaining = reading === null ? null : reading - vehicle.reading;
  const days = day === null ? null : Math.round((Date.parse(day) - Date.parse(date)) / 86400000);
  const overdue = (remaining !== null && remaining <= 0) || (days !== null && days <= 0);
  const soon = (remaining !== null && remaining <= Math.min(vehicle.unit === 'km' ? 1000 : 50, task.interval * .1)) || (days !== null && days <= 30);
  return { reading, day, remaining, days, status: overdue ? 'Scaduto' : soon ? 'In scadenza' : 'Regolare' };
}
export function complete(data, vehicleId, taskIds, entry) {
  const vehicle = data.vehicles.find(v => v.id === vehicleId);
  const extras=entry.items??[];
  if (!Array.isArray(extras)||extras.length>40||extras.some(i=>!i||typeof i.name!=='string'||!i.name.trim()||i.name.length>100||typeof i.part!=='string'||i.part.length>120)||new Set(extras.map(i=>i.name.trim().toLowerCase())).size!==extras.length) throw Error('Lavori aggiunti non validi.');
  if (!vehicle || !(taskIds.length+extras.length)) throw Error('Seleziona almeno un intervento.');
  if (!num(entry.reading) || entry.reading < vehicle.reading) throw Error('Il contatore non può essere inferiore al valore attuale.');
  if (vehicle.unit === 'km' && !Number.isInteger(entry.reading)) throw Error('Inserisci chilometri interi.');
  if (!validDate(entry.date) || entry.date > today()) throw Error('Inserisci una data valida, non futura.');
  if (!num(entry.cost)) throw Error('Inserisci un costo valido.');
  if (!validPhotos(entry.photos)) throw Error('Allegati foto non validi.');
  const tasks = data.tasks.filter(t => t.vehicleId === vehicleId && taskIds.includes(t.id));
  if (tasks.length !== taskIds.length) throw Error('Interventi non validi.');
  if (tasks.some(t => entry.date < t.lastDate || entry.reading < t.lastReading)) throw Error('La registrazione precede l’ultimo intervento del piano.');
  const result = structuredClone(data);
  result.vehicles.find(v => v.id === vehicleId).reading = entry.reading;
  result.tasks.filter(t => taskIds.includes(t.id)).forEach(t => { t.lastReading = entry.reading; t.lastDate = entry.date; });
  result.history.unshift({ ...entry, id: crypto.randomUUID(), vehicleId, vehicleName: vehicle.name, vehicleType: vehicle.type, unit: vehicle.unit, items: [...tasks.map(t => ({ name: t.name, part: t.part })),...extras.map(i=>({name:i.name.trim(),part:i.part.trim()}))] });
  return result;
}
function validateV1(d) {
  if (!Array.isArray(d.vehicles) || !Array.isArray(d.tasks) || !Array.isArray(d.history)) throw Error('Backup non valido.');
  if (d.vehicles.some(v => !identifier(v.id) || !str(v.name) || !str(v.model) || !str(v.serial) || !str(v.power) || !num(v.hours))) throw Error('Anagrafica non valida.');
  const ids = new Set(d.vehicles.map(v => v.id));
  if (ids.size !== d.vehicles.length || new Set(d.tasks.map(t => t.id)).size !== d.tasks.length) throw Error('Identificativi duplicati.');
  if (d.tasks.some(t => !identifier(t.id) || !ids.has(t.vehicleId) || !str(t.name) || !str(t.part) || !num(t.hours) || !num(t.months) || !Number.isInteger(t.months) || !(t.hours || t.months) || !num(t.lastHours) || !validDate(t.lastDate) || t.lastHours > d.vehicles.find(v => v.id === t.vehicleId).hours)) throw Error('Piano non valido.');
  if (d.history.some(h => !identifier(h.id) || !str(h.vehicleName) || !ids.has(h.vehicleId) || !validDate(h.date) || !num(h.hours) || !num(h.cost) || !str(h.technician) || !str(h.notes) || !validPhotos(h.photos) || !Array.isArray(h.items) || h.items.some(i => !str(i.name) || !str(i.part)))) throw Error('Storico non valido.');
}
export function validateBackup(d) {
  if (d?.version === 1) {
    validateV1(d);
    // Trasforma una copia: il vecchio archivio rimane intatto fino al salvataggio.
    d = {
      version: 2,
      vehicles: d.vehicles.map(({ hours, ...v }) => ({ ...v, type: 'forklift', unit: 'h', reading: hours, plate: '' })),
      tasks: d.tasks.map(({ hours, lastHours, ...t }) => ({ ...t, interval: hours, lastReading: lastHours })),
      history: d.history.map(({ hours, ...h }) => ({ ...h, reading: hours, unit: 'h', vehicleType: 'forklift' }))
    };
  }
  if (d?.version !== 2 || !Array.isArray(d.vehicles) || !Array.isArray(d.tasks) || !Array.isArray(d.history)) throw Error('Backup non valido.');
  if (d.vehicles.some(v => !identifier(v.id) || !str(v.name) || !str(v.model) || !str(v.serial) || !str(v.plate) || !str(v.power) || !Object.hasOwn(vehicleTypes, v.type) || !['h', 'km'].includes(v.unit) || !num(v.reading) || (v.unit === 'km' && !Number.isInteger(v.reading)))) throw Error('Anagrafica non valida.');
  const ids = new Set(d.vehicles.map(v => v.id));
  if (ids.size !== d.vehicles.length || new Set(d.tasks.map(t => t.id)).size !== d.tasks.length) throw Error('Identificativi duplicati.');
  if (d.tasks.some(t => !identifier(t.id) || !ids.has(t.vehicleId) || !str(t.name) || !str(t.part) || !num(t.interval) || !num(t.months) || !Number.isInteger(t.months) || !(t.interval || t.months) || !num(t.lastReading) || !validDate(t.lastDate) || t.lastReading > d.vehicles.find(v => v.id === t.vehicleId).reading || (d.vehicles.find(v => v.id === t.vehicleId).unit === 'km' && (!Number.isInteger(t.interval) || !Number.isInteger(t.lastReading))))) throw Error('Piano non valido.');
  if (d.history.some(h => !identifier(h.id) || !str(h.vehicleName) || !ids.has(h.vehicleId) || !validDate(h.date) || !num(h.reading) || !['h', 'km'].includes(h.unit) || !Object.hasOwn(vehicleTypes, h.vehicleType) || !num(h.cost) || !str(h.technician) || !str(h.notes) || !validPhotos(h.photos) || !Array.isArray(h.items) || h.items.some(i => !str(i.name) || !str(i.part)))) throw Error('Storico non valido.');
  return d;
}
export const blank = () => ({ version: 2, vehicles: [], tasks: [], history: [] });
