const path = require('path');

module.exports = {
  entry: path.join(__dirname, 'index.js'),
  resolve: {
    extensions: ['.js', '.elm'],
    modules: ['node_modules']
  },
  module: {
    rules: [{
      test: /\.elm$/,
      exclude: [/elm-stuff/, /node_modules/],
      use: {
        loader: 'elm-webpack-loader',
        options: {
          warn: true,
        }
      }
    }]
  },
  output: {
    filename: 'app.js'
  }
};
