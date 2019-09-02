const path = require('path');
const HtmlWebpackPlugin = require('html-webpack-plugin');
const ExtractTextPlugin = require('extract-text-webpack-plugin');
const CopyWebpackPlugin = require('copy-webpack-plugin');

const outputPath = path.join(__dirname, '..', 'dist');

module.exports = {
  entry: [
    path.join(__dirname, 'index.js'),
  ],
  resolve: {
    extensions: ['.js', '.elm'],
    modules: ['node_modules']
  },
  module: {
    rules: [
      {
        test: /\.elm$/,
        exclude: [/elm-stuff/, /node_modules/],
        use: {
          loader: 'elm-webpack-loader',
          options: {
          }
        }
      },
      {
        test: /\.scss$/,
        use: [{
          loader: "css-loader"
        }, {
          loader: "sass-loader",
        }]
      },
      {
        test: /\.(ttf|otf|eot|svg|woff(2)?)(\?[a-z0-9\=\#\.]+)?$/,
        use: {
          loader: 'file-loader',
          options: {
            outputPath: 'static/',
          },
        },
      },
      { // sass / scss loader for webpack
        test: /\.(sass|scss)$/,
        loader: ExtractTextPlugin.extract(['css-loader', 'sass-loader'])
      }
    ],
  },
  plugins: [
    new ExtractTextPlugin({
      filename: 'app.css',
      allChunks: true,
    }),
    new CopyWebpackPlugin([
      {
        from: 'assets/images/**/*',
        to: 'static/images',
        flatten: true,
      }
    ]),
    new HtmlWebpackPlugin({
      template: 'index.ejs',
    }),
  ],
  output: {
    filename: 'app.js',
    path: outputPath,
  }
};
