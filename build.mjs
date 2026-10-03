import {mkdir,copyFile,cp,rm} from 'node:fs/promises';
await rm('dist',{recursive:true,force:true});await mkdir('dist');await copyFile('index.html','dist/index.html');await cp('src','dist/src',{recursive:true});console.log('Build pronto in dist/');
