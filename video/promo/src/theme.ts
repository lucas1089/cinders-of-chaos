import {continueRender, delayRender, staticFile} from 'remotion';

export const colors = {
  bg: '#0b0706',
  ember: '#ff7a2a',
  emberDeep: '#b8321a',
  gold: '#e8c48a',
  text: '#f6ead6',
  shade: 'rgba(8, 4, 3, 0.82)',
};

export const fonts = {
  title: 'ChaosCinzel, serif',
  body: 'ChaosAlegreya, sans-serif',
};

// The client's own OFL fonts (client/fonts-src), copied to public/fonts by tools/prepare.sh.
let loaded = false;
export const loadFonts = () => {
  if (loaded || typeof document === 'undefined') {
    return;
  }
  loaded = true;
  const handle = delayRender('fonts');
  const faces = [
    new FontFace('ChaosCinzel', `url(${staticFile('fonts/Cinzel.ttf')})`, {weight: '400 900'}),
    new FontFace('ChaosAlegreya', `url(${staticFile('fonts/AlegreyaSans-Medium.ttf')})`, {weight: '500'}),
  ];
  Promise.all(faces.map((f) => f.load()))
    .then((list) => {
      list.forEach((f) => document.fonts.add(f));
      continueRender(handle);
    })
    .catch((err) => {
      console.error(err);
      continueRender(handle);
    });
};
