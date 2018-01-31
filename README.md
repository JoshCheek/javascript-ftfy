Javascript... FTFY
==================

A JS interpreter that uses continuations so that you can write synchronous code,
as if you were in a language like Ruby or Python, but the code will still run
asynchronously, without blocking.


How to use
----------

At present, it's only useful to show that you can write synchronous code that
runs asynchronously.

The output is specifically crafted to allow the Atom Editor plugin to modify
the JS file that it ran, and update the contents of the buffer with the results.

To use with Atom, from this project's root:

```
$ ln -s "$PWD"/atom-editor-plugin/  "$HOME"/.atom/packages/javascript-ftfy-atom
```

Then reload your Atom window, you can use:

* Cmd-Opt-J to display the results
* Cmd-Opt-K to clear the results


Install
-------

This requires you to have a Ruby interpreter, and a JS interpreter. IDK what
versions of those that it needs, but locally, mine are Ruby 2.5.0, and Node 8.9.4

```
$ npm install
$ bundle install # if this fails, `gem install bundler` and try again
```


Test
----

```
$ rspec
```


License
-------

It'd be cool if you credit me, if you get something cool done with it.
But if you can convince JS to adopt this for real, that's plenty.

[MIT](https://opensource.org/licenses/MIT)