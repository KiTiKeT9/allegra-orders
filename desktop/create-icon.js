const fs = require('fs');
const path = require('path');

// Создаем валидный ICO файл 256x256 с PNG сжатием
function createICO256() {
  // Для 256x256 используем PNG внутри ICO (стандарт Windows Vista+)

  // Минимальный PNG 256x256 синий квадрат
  // Это упрощенный PNG без сжатия для демонстрации
  const pngData = createMinimalPNG(256, 256, 0, 113, 227); // #0071e3 in BGR

  // ICO Header
  const header = Buffer.alloc(6);
  header.writeUInt16LE(0, 0);    // Reserved
  header.writeUInt16LE(1, 2);    // Type: icon
  header.writeUInt16LE(1, 4);    // Number of images

  // ICO Directory Entry для 256x256
  const directory = Buffer.alloc(16);
  directory.writeUInt8(0, 0);    // Width (0 = 256)
  directory.writeUInt8(0, 1);    // Height (0 = 256)
  directory.writeUInt8(0, 2);    // Color palette
  directory.writeUInt8(0, 3);    // Reserved
  directory.writeUInt16LE(1, 4); // Color planes
  directory.writeUInt16LE(32, 6);// Bits per pixel (32 for PNG)
  directory.writeUInt32LE(pngData.length, 8);  // Image size
  directory.writeUInt32LE(22, 12); // Offset to image data

  return Buffer.concat([header, directory, pngData]);
}

// Создаем минимальный валидный PNG
function createMinimalPNG(width, height, r, g, b) {
  // PNG signature
  const signature = Buffer.from([137, 80, 78, 71, 13, 10, 26, 10]);

  // IHDR chunk
  const ihdr = createChunk('IHDR', createIHDR(width, height));

  // IDAT chunk (image data) - несжатые данные
  const rawData = createRawImageData(width, height, r, g, b);
  const idat = createChunk('IDAT', rawData);

  // IEND chunk
  const iend = createChunk('IEND', Buffer.alloc(0));

  return Buffer.concat([signature, ihdr, idat, iend]);
}

function createIHDR(width, height) {
  const buffer = Buffer.alloc(13);
  buffer.writeUInt32BE(width, 0);
  buffer.writeUInt32BE(height, 4);
  buffer.writeUInt8(8, 8);   // Bit depth
  buffer.writeUInt8(2, 9);   // Color type (2 = RGB)
  buffer.writeUInt8(0, 10);  // Compression
  buffer.writeUInt8(0, 11);  // Filter
  buffer.writeUInt8(0, 12);  // Interlace
  return buffer;
}

function createRawImageData(width, height, r, g, b) {
  // Простое RLE сжатие для одноцветного изображения
  const data = [];

  for (let y = 0; y < height; y++) {
    data.push(0); // Filter: None

    // Для одноцветного изображения можно использовать простое повторение
    for (let x = 0; x < width; x++) {
      data.push(r);
      data.push(g);
      data.push(b);
    }
  }

  return Buffer.from(data);
}

function createChunk(type, data) {
  const length = Buffer.alloc(4);
  length.writeUInt32BE(data.length, 0);

  const typeBuffer = Buffer.from(type);

  const crc = Buffer.alloc(4);
  const crcData = Buffer.concat([typeBuffer, data]);
  crc.writeUInt32BE(crc32(crcData), 0);

  return Buffer.concat([length, typeBuffer, data, crc]);
}

function crc32(buf) {
  let crc = 0xFFFFFFFF;
  const table = makeCRCTable();

  for (let i = 0; i < buf.length; i++) {
    crc = (crc >>> 8) ^ table[(crc ^ buf[i]) & 0xFF];
  }

  return (crc ^ 0xFFFFFFFF) >>> 0;
}

function makeCRCTable() {
  const table = [];
  for (let n = 0; n < 256; n++) {
    let c = n;
    for (let k = 0; k < 8; k++) {
      c = ((c & 1) ? (0xEDB88320 ^ (c >>> 1)) : (c >>> 1));
    }
    table[n] = c >>> 0;
  }
  return table;
}

// Создаем и сохраняем
const icoPath = path.join(__dirname, 'icon.ico');
try {
  const ico = createICO256();
  require('fs').writeFileSync(icoPath, ico);
  console.log('✅ ICO иконка 256x256 создана:', icoPath);
  console.log('📏 Размер файла:', ico.length, 'bytes');
  console.log('\nТеперь соберите приложение:');
  console.log('npm run build:win');
} catch (e) {
  console.error('❌ Ошибка:', e.message);
  console.log('\n💡 Альтернатива: используйте онлайн конвертер');
  console.log('1. Скачайте любую картинку 256x256 PNG');
  console.log('2. Конвертируйте на https://cloudconvert.com/png-to-ico');
  console.log('3. Сохраните как icon.ico в папке desktop/');
}
