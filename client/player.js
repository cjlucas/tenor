class Player {
  constructor(eventHandler) {
    this.eventHandler = eventHandler;
    this.currentID = null;
    this.players = {};

    setInterval(() => {
      if (this.player && this.player.playing()) {
        this.eventHandler({
          type: 'seek',
          time: this.player.seek()
        });
      }
    }, 300);
  }

  reset() {
    Object.keys(this.players).forEach(id => this.unload(id));
    this.currentID = null;
  }

  play(id) {
    if (id !== undefined) {
      this.unload(this.currentID);
      this.currentID = id;
    }

    const player = this._currentPlayer();
    if (!player) {
      console.error(`No player found for id: ${id}`);
      return;
    }

    player.play();
  }

  unload(id) {
    const player = this.players[id];
    if (player) {
      player.unload();
      delete this.players[id];
    }
  }

  load(id, url) {
    this._registerPlayer(id, url);
  }

  pause() {
    const player = this._currentPlayer();
    if (player) {
      player.pause();
    }
  }

  _currentPlayer() {
    return this.players[this.currentID];
  }

  _registerPlayer(id, url) {
    const player = new Howl({
      src: [url],
      format: ['mp3'],
      autoplay: false,
    });

    this.players[id] = player;

    const events = ['load', 'loaderror', 'play', 'end', 'pause', 'stop', 'seek'];
    events.forEach(event => {
      player.on(event, e => {
        this.eventHandler({
          type: event,
          id: id,
        });
      });
    });
  }
}
