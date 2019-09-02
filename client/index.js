import Player from './player';
import { Elm } from './src/Main';
import css from './app.scss';

const app = Elm.Main.init({
  node: document.getElementById("body")
});

const player = new Player(app.ports.playerEvent.send);

window.player = player;

app.ports.play_.subscribe(() => {
  player.play();
});

app.ports.playId.subscribe(id => {
  player.play(id);
});

app.ports.load_.subscribe(({id, url}) => {
  console.log(`load: ${id} ${url}`);
  player.load(id, url)
});

app.ports.unload.subscribe(id => {
  console.log(`unload: ${id}`);
  player.unload(id);
});

app.ports.pause_.subscribe(() => {
  player.pause();
});

app.ports.reset_.subscribe(() => {
  player.reset();

  app.ports.playerEvent.send({
    type: 'reset'
  });
});
