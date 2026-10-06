import {MAX_PHOTO_BYTES,validPhotos} from './domain.js?v=8';

export async function preparePhoto(file) {
  if (!file.type.startsWith('image/')) throw Error('Seleziona un file immagine.');
  if (file.size > 20000000) throw Error('La foto supera 20 MB. Scegli un’immagine più piccola.');
  const url = URL.createObjectURL(file);
  try {
    const image = new Image();
    image.src = url;
    try { await image.decode(); } catch { throw Error('Foto non leggibile. Prova con JPEG, PNG o WebP.'); }
    const canvas = document.createElement('canvas');
    const ratio = Math.min(1, 1280 / Math.max(image.naturalWidth, image.naturalHeight));
    canvas.width = Math.max(1, Math.round(image.naturalWidth * ratio));
    canvas.height = Math.max(1, Math.round(image.naturalHeight * ratio));
    const context = canvas.getContext('2d');
    if (!context) throw Error('Il browser non riesce a preparare la foto.');
    context.fillStyle = '#fff';
    context.fillRect(0, 0, canvas.width, canvas.height);
    context.drawImage(image, 0, 0, canvas.width, canvas.height);
    for (const quality of [.8, .65, .5, .35, .2]) {
      const dataUrl = canvas.toDataURL('image/jpeg', quality);
      if ((dataUrl.length - dataUrl.indexOf(',') - 1) * 3 / 4 <= MAX_PHOTO_BYTES) {
        return {name: (file.name.replace(/\.[^.]*$/, '') || 'foto').slice(0, 190) + '.jpg', dataUrl};
      }
    }
    throw Error('Foto troppo complessa da comprimere. Scegli un’immagine più piccola.');
  } finally { URL.revokeObjectURL(url); }
}

export function photoBlob(photo) {
  if (!validPhotos([photo])) throw Error('Allegato foto non valido.');
  const [header,base64] = photo.dataUrl.split(',');
  const bytes = Uint8Array.from(atob(base64), c => c.charCodeAt(0));
  return new Blob([bytes], {type:header.slice(5).split(';')[0]});
}
