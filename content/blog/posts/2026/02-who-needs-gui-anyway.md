---
title: Who needs GUIs anyway?
summary: My frustrations with desktop UI, especially GUI toolkits
author: Nathan Gill
date: 2026-02-02
template: blog.html
type: blog
---

For the past few months I've found that I only really use two applications.
One, a web browser (yeah the title's a bit misleading); two, a terminal
emulator.

A particular frustration I have is with other graphical tools, that includes
pretty much *everything* built with toolkits like GTK and Qt. I've found myself
specifically going out of my way to install CLI alternatives to pretty much
everything I can, especially when looking for new stuff (like, "oh hell it
uses gtk", *moves on*).

Anyway, I have a specific problem with these two toolkits, and spend a decent
chunk of my time purging them from my system.

# An example

A pretty good example was the other week when I was doing a thing with DBUS
secret service, provided by `gnome-keyring` on my system. Despite the name,
that tool was not my problem, as it's actually just a service. My problem
was I needed to view the things I had saved to the keyring, to make sure
my program was actually saving the right data.

Naturally, the first thing I do is look for a tool that can dump the contents
of which there were a few, including CLI options. The initial one I looked at
worked, but there didn't appear to be a way for me to dump *everything*, which
was right annoying for my use case.

After other events, which I won't go into detail here, I found a GUI tool
called Seahorse that could do it. Unfortunately, it uses GTK, and is actually
a built-in GNOME thing (I don't know why all their things are named after sea
creatures). Despite the fact I'd be using it in a **temporary** Nix shell, I
didn't like the idea of installing it.

# Why?

I've built a few things with graphical toolkits, and have pretty quickly found
that there's pretty much nothing you can do with a GUI that you can't do in a
CLI shell.

Both of these toolkits are pretty heavy, and, from my point of view, try to do
too much for you. A pretty good way to think about it is to compare these
toolkits to web browser engines. At this point, they pretty much are; GTK
supports CSS natively, a language literally *designed* for the web, not
desktops. Qt supports things like QML, which again, feels like a web thing.

One, if I'm going to have a web engine, I want it in one place, a web browser, where
it's supposed to be. Mainly because they are **massive**, I know Qt is a packaging
nightmare, divided into hundreds of modular libraries that are completely
incompatible with versions just slightly out-of-date. I don't know about GTK,
but I assume it's a similar story.

Two, a web browser is probably good enough. Modern web browsers have (mostly) enough
support for anything you could need to do with a GUI, native messaging is a pretty
good example, letting a browser VM interface with pretty much anything on the
system. For example, it's perfectly plausible to have a local tool that runs in CLI
only, build web UI around it, and invoke the local tool. This is much more flexible
for users (like me) who would rather use what I want.

Three, it's actually *much* easier to build web UI than desktop UI in my experience.
With GTK, you could compare it to building a HTML document, complete with styling,
manually, purely in JavaScript - constructing everything node-by-node, and assigning
styles manually. Literally what frameworks like React give you for free.
Funnily enough, from my time on Windows, it's also a hell of a lot easier to build
UI with plain Win32 than frameworks like GTK and Qt.

Four, standardisation. Neither of the common desktop GUI toolkits have any kind of
common standard (that I know of). Everything you tweak has to be done separately,
normally in a way that is tightly integrated with a desktop environment, for
example, both GNOME and KDE suffer from this problem, everything is too tightly
integrated. Whereas, on web platforms, at least there's a common set of ways to
get things done, really improving interoperability.

Five, does it really need to be complicated? Do you really need a GUI at all? A
CLI is much simpler and, with some work, is just as "user-friendly", also,
standards.

# tl;dr

GUI toolkits are problematic. They are big, complex, hard to maintain, and are
fundamentally, not needed anymore. If you need a GUI, a web browser provides
a much better platform to run one, while still maintaining flexibility, for
those who prefer otherwise.

