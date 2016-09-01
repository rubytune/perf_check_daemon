(function e(t,n,r){function s(o,u){if(!n[o]){if(!t[o]){var a=typeof require=="function"&&require;if(!u&&a)return a(o,!0);if(i)return i(o,!0);var f=new Error("Cannot find module '"+o+"'");throw f.code="MODULE_NOT_FOUND",f}var l=n[o]={exports:{}};t[o][0].call(l.exports,function(e){var n=t[o][1][e];return s(n?n:e)},l,l.exports,e,t,n,r)}return n[o].exports}var i=typeof require=="function"&&require;for(var o=0;o<r.length;o++)s(r[o]);return s})({1:[function(require,module,exports){

window.BrowserApp = require("./src/browser-app.js.jsx").BrowserApp;

},{"./src/browser-app.js.jsx":2}],2:[function(require,module,exports){
/*
Copyright (c) 2016 Peter Woo

Permission is hereby granted, free of charge, to any person obtaining a copy of this software and associated documentation files (the "Software"), to deal in the Software without restriction, including without limitation the rights to use, copy, modify, merge, publish, distribute, sublicense, and/or sell copies of the Software, and to permit persons to whom the Software is furnished to do so, subject to the following conditions:

The above copyright notice and this permission notice shall be included in all copies or substantial portions of the Software.

THE SOFTWARE IS PROVIDED "AS IS", WITHOUT WARRANTY OF ANY KIND, EXPRESS OR IMPLIED, INCLUDING BUT NOT LIMITED TO THE WARRANTIES OF MERCHANTABILITY, FITNESS FOR A PARTICULAR PURPOSE AND NONINFRINGEMENT. IN NO EVENT SHALL THE AUTHORS OR COPYRIGHT HOLDERS BE LIABLE FOR ANY CLAIM, DAMAGES OR OTHER LIABILITY, WHETHER IN AN ACTION OF CONTRACT, TORT OR OTHERWISE, ARISING FROM, OUT OF OR IN CONNECTION WITH THE SOFTWARE OR THE USE OR OTHER DEALINGS IN THE SOFTWARE.
*/

exports.BrowserApp = React.createClass({
  displayName: "BrowserApp",

  propTypes: {
    searchPath: React.PropTypes.string.isRequired,
    searchPlaceholder: React.PropTypes.string,

    // Tag to wrap filter results with
    resultTag: React.PropTypes.oneOfType([React.PropTypes.string, React.PropTypes.func]),

    initialFilter: React.PropTypes.string,
    initialResults: React.PropTypes.array,
    initialSelectedResult: React.PropTypes.oneOfType([React.PropTypes.string, React.PropTypes.number]),

    // Called after filter search/refresh
    onFilter: React.PropTypes.func,

    // Called after a filter result is selected
    onSelect: React.PropTypes.func,

    // Called after content is loaded into the viewport
    onLoad: React.PropTypes.func,

    // Called before content is unloaded from the viewport
    onUnload: React.PropTypes.func
  },

  getDefaultProps: function () {
    return {
      onFilter: function () {},
      onSelect: function () {},
      onLoad: function () {},
      onUnload: function () {}
    };
  },

  getInitialState: function () {
    return {
      filter: this.props.initialFilter || "",

      // filter results
      results: this.props.initialResults || [],

      // .id of selected filter result
      selectedResult: this.props.initialSelectedResult || null,

      // url of the content displayed in the viewport
      viewPortUrl: null,

      // content displayed in the viewport
      viewportHTML: this.props.__html || this.props.children || ""
    };
  },

  componentDidMount: function () {
    this.refs.ui.parentNode.style.height = "100%";

    window.onpopstate = this.popHistory;
  },

  ajax: function (url, data, callback) {
    var self = this;

    var pairs = [],
        keys = Object.keys(data);
    for (var i = 0; i < keys.length; ++i) pairs.push(encodeURIComponent(keys[i]) + "=" + encodeURIComponent(data[keys[i]]));

    if (pairs.length) {
      url += url.match(/\?./) ? "&" : url.match(/\?/) ? "" : "?";
      url += pairs.join("&");
    }

    var xhttp = new XMLHttpRequest();
    xhttp.onreadystatechange = function () {
      if (xhttp.readyState == 4 && xhttp.status == 200) callback.call(self, xhttp.responseText);
    };
    xhttp.open("GET", url, true);
    xhttp.send();
  },

  pushHistory: function (url) {
    url = url || location.pathname;
    if (this.state.filter.match(/\S/)) {
      url += url.match(/\?./) ? "&" : url.match(/\?/) ? "" : "?";
      url += "f=" + encodeURIComponent(this.state.filter);
    }

    window.history.pushState({
      filter: this.state.filter || "",
      selectedResult: this.state.selectedResult
    }, '', url);
  },

  popHistory: function (e) {
    if (e.state && e.state.filter != this.state.filter) this.filter(e.state.filter);

    this.setViewport(location.href, e.state ? e.state.selectedResult : this.props.initialSelectedResult, false);
  },

  filter: function (f, callback) {
    var self = this;
    this.ajax(this.props.searchPath, { f: f }, function (resp) {
      resp = JSON.parse(resp);
      self.setState({ filter: f, results: resp.results }, function () {
        self.pushHistory();
        self.props.onFilter(resp);
        callback && callback(resp);
      });
    });
  },

  refreshFilter: function (e) {
    e && e.preventDefault();
    this.filter(this.state.filter);
  },

  clearFilter: function (e) {
    e && e.preventDefault();

    var self = this;
    this.filter("", function () {
      self.refs.filter.focus();
      self.refs.filter.select();
    });
  },

  setViewport: function (url, id, save, callback) {
    if (this.props.onUnload() === false) return false;

    var self = this;
    this.ajax(url, {}, function (html) {
      self.setState({
        selectedResult: id,
        viewportUrl: url,
        viewportHTML: html
      });

      if (save !== false) this.pushHistory(url);

      callback && callback();
    });

    return true;
  },

  onFilterInputChange: function (e) {
    this.setState({ filter: e.target.value });
  },

  onSelectResult: function (id, url, e) {
    if (url && ["A", "BUTTON", "INPUT", "TEXTAREA"].indexOf(e.target.nodeName) == -1) {
      e.preventDefault();
      this.setViewport(url, id, true, this.props.onSelect);
    } else if (url && e.target.nodeName == "A" && e.target.attributes.href.value == url) {
      e.preventDefault();
      this.setViewport(url, id, true, this.props.onSelect);
    }
  },

  render: function () {
    var self = this;

    var resultTag = this.props.resultTag;
    if (typeof resultTag == "string") resultTag = window[resultTag];

    var results = this.state.results.map(function (result) {
      var selected = self.state.selectedResult !== null && result.id == self.state.selectedResult;
      if (resultTag) {
        var e = React.createElement(resultTag, result);
        return React.createElement(
          "li",
          { key: result.id,
            className: selected ? "browser-app-selected" : "",
            onClick: self.onSelectResult.bind(self, result.id, result.url) },
          e
        );
      } else if (result.html) {
        return React.createElement("li", { key: result.id,
          className: selected ? "browser-app-selected" : "",
          onClick: self.onSelectResult.bind(self, result.id, result.url),
          dangerouslySetInnerHTML: { __html: result.html } });
      }
    });

    if (results.length) results.push(React.createElement(
      "li",
      { key: "-1", style: { textAlign: "center" } },
      "No more results"
    ));else results.push(React.createElement(
      "li",
      { key: "-1", style: { textAlign: "center" } },
      "No results"
    ));

    var content = typeof this.state.viewportHTML == "string" ? React.createElement("div", { className: "browser-app-viewport-content",
      dangerouslySetInnerHTML: { __html: this.state.viewportHTML } }) : React.createElement(
      "div",
      { className: "browser-app-viewport-content" },
      this.state.viewportHTML
    );

    return React.createElement(
      "div",
      { ref: "ui", className: "browser-app" },
      React.createElement(
        "div",
        { className: "browser-app-filter" },
        React.createElement(
          "form",
          { action: this.props.searchPath, onSubmit: this.refreshFilter },
          React.createElement(
            "div",
            { className: "browser-app-filter-container" },
            React.createElement(
              "span",
              { className: "browser-app-filter-clear", onClick: this.clearFilter },
              React.createElement(
                "a",
                { href: "#" },
                React.createElement("i", { className: "fa fa-ban" })
              )
            ),
            React.createElement("input", { ref: "filter", type: "search", name: "f", autoComplete: "off",
              placeholder: this.props.searchPlaceholder, value: this.state.filter, onChange: this.onFilterInputChange })
          )
        ),
        React.createElement(
          "ul",
          { className: "browser-app-results" },
          results
        )
      ),
      React.createElement(
        "div",
        { className: "browser-app-viewport" },
        content
      )
    );
  }
});

},{}]},{},[1]);
