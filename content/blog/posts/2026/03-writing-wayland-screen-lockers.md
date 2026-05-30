---
title: Writing Wayland screen lockers "for fun"
summary: Yes, I wrote (or at least tried to write) more than one.
author: Nathan Gill
date: 2026-03-05
template: blog.html
type: blog
---

**Note:** This blog post does not actually cover how to write a Wayland screen
locker yourself, just the engineering process of my own implementation. Sorry :(

---

About 10 months ago I stopped using GNOME on my main system in favour of a
tiling window manager, Sway in my case. Kind of an accident actually, but
that's a different story. At the same time, I changed out my display manager
since GDM was (I assumed) quite closely tied to GNOME, which I planned on
removing. I ended up using SDDM, mainly because it's pretty easy to customise
via QML, and could give me some nice theming rather than the rather fixed layout
of GDM.

In my search for cool SDDM themes that I actually liked, I came across the
minimalist, rather cool-looking, [where-is-my-sddm-theme][where-is-my-sddm-theme].
I still use this today. However, after about a month of using this, something
kind of felt inconsistent, specifically the screen locker I was using,
[Swaylock][swaylock]. Now I have nothing against Swaylock, it's a pretty
standard choice on many wlroots compositors, however, wouldn't it be cool if
my display manager and screen locker shared the same theme? Swaylock, by design,
locks you into a particular layout, which I couldn't really adapt to fit with
the theme I liked. It was time for me to search for something else...

---

# Enter wlockr

Right. After doing a decent amount of research into this I hadn't really
gotten anywhere other than a comment somewhere suggesting I could modify
[Hyprlock][hyprlock], but I wasn't using Hyprland, and didn't feel like
introducing a bunch of dependencies. I started taking a look at how I could
build my own instead, something that:

- Natively supported the kind of layout I wanted,
- Would allow me to deeply customise it around this base layout,
- Was more compatible and lighter than something like Hyprlock.

During my research, I stumbled upon [Waylock][waylock] which seemed like a
decent reference point for the basics a screen locker should do. Unfortunately,
it is written in Zig, which wasn't a language I knew at the time (and hardly do
now). Coincidentally, I had recently found I quite liked Rust, not to say I had
a great deal of experience with it at the time though. I would write mine in
Rust anyway. This would also be my first time writing anything that interacted
directly with Wayland, rather than going through a UI toolkit.

My first attempt at implementing a screen locker takes the form of [wlockr][wlockr],
basically just an experiment to see if I could get anything working. I did, well,
it worked *at least once* - before I broke it again. Funnily enough, that's the
state of the repository too, so **don't** run wlockr yourself unless your hobby
involves bricking compositor sessions and losing work for some reason. It didn't
do any proper authentication either, which proved to be a further problem down
the line.

Nevertheless, wlockr gave me some sort of hope I might actually be capable of
writing this thing. No, it didn't do much but it demonstrated the core stuff I
would need later.

---

# tlockr: The Plan

After wlockr, I started to formulate how I would build the "final" thing,
which I'd named [tlockr][tlockr], based almost exclusively on the little I had
from wlockr. This is the point where, from my perspective now, things started
to go wrong. I'm no longer building a small screen locker that implemented this
theme. Hell no, that's too simple. No. I'm building a screen locker with: fully
dynamic, user selectable QML content; "infinite customisability"; and
hardware-accelerated rendering. SDDM (kind of) does something similar. Did I
know how to implement any of this? No.

## tlockr: The Reality

This is obviously a recipe for disaster if you didn't see already. Not to
mention the sheer level of overengineering. I didn't need any of this to
achieve what I wanted. To make matters worse, I decided to write all the Qt
stuff in C++ for some reason, which made FFI, and the bespoke event system
associated with it a truly hellish nightmare. Remember, this is a screen locker,
not fucking DOOM or something of the like.

For my own embarrassment I'll go through some of the horrific garbage that I
ended up writing for tlockr.

Some of the worst offenders can be found at the Rust/C++ boundary and the event
system between them.

### #1: `EventParam(u64)`

tlockr's event system basically relies on passing around a pair of `u64`s and
interpreting them as needed. This is not an inherently bad design when used
for example, simple numeric values, flags, among others.

Passing raw pointers is not one of these, especially on different
architectures.

```rs
#[derive(Debug, Clone, Copy)]
pub struct EventParam(u64);

/* ... */

impl From<EventParam> for *mut c_void {
    fn from(param: EventParam) -> Self {
        param.0 as *mut c_void
    }
}
```

### #2: Callback hell

How about one of these wonderful callbacks hooking directly into the rendering
pipeline? This is bad. I didn't even check `user_data` wasn't null, and is
clearly an architectural issue itself.

```rs
unsafe extern "C" fn get_buffer_callback(user_data: *mut c_void) -> *mut c_void {
    let buffer_manager = user_data as *mut BufferManager;
    unsafe {
        buffer_manager
            .as_ref()
            .and_then(|bm| bm.find_available_buffer())
            .map(|b| b.data as *mut c_void)
            .unwrap_or(std::ptr::null_mut())
    }
}
```

### #3: "Safe" macros

We also have some "safe" macros designed to get around the type system. Naively
manipulating shared state directly through raw pointers is a good recipe for
concurrency problems. I mean, at least I'm checking for null first...?

```rs
macro_rules! safe_getter {
    ($fn_name:ident, $field:ident, $return_type:ty) => {
        pub fn $fn_name(ptr: *const ApplicationState) -> Option<$return_type> {
            if ptr.is_null() {
                return None;
            }
            Some(unsafe { (*ptr).$field })
        }
    };
}

macro_rules! safe_setter {
    ($fn_name:ident, $field:ident, $param_type:ty) => {
        pub fn $fn_name(ptr: *mut ApplicationState, value: $param_type) -> bool {
            if ptr.is_null() {
                return false;
            }
            unsafe {
                (*ptr).$field = value;
            }
            true
        }
    };
}

/* ... */

safe_getter!(get_state, state, State);
safe_getter!(get_renderer_read_fd, renderer_read_fd, c_int);
safe_getter!(get_renderer_write_fd, renderer_write_fd, c_int);

/* ... */


safe_setter!(set_state, state, State);
safe_setter!(set_renderer_read_fd, renderer_read_fd, c_int);
safe_setter!(set_renderer_write_fd, renderer_write_fd, c_int);
```

### #4: "QmlRenderer"

As the Qt stuff grew to handle input event translation and injection, and, well
everything in the C++/Qt thread, the name `QmlRenderer` lost quite a bit of
meaning. Also, what the fuck is `Interface`???

```cpp
struct QmlRenderer {
    QGuiApplication *app;
    QSize fbSize;
    QOpenGLContext *context;
    QSurfaceFormat *surfaceFormat;
    QOffscreenSurface *surface;
    QQuickRenderControl *renderControl;
    QQuickWindow *window;
    QOpenGLFramebufferObjectFormat *fbFormat;
    QOpenGLFramebufferObject *fb;
    QQmlEngine *engine;
    QQmlComponent *component;
    QSocketNotifier *eventSocketNotifier;
    QQuickItem *rootItem;

    const char *qmlPath;
    bool running = false;

    RsGetBufferCallback getBufferCallback = nullptr;
    void *userData = nullptr;

    std::thread renderThread;
    std::atomic<bool> threadRunning{false};
    std::atomic<bool> shouldStop{false};
    std::mutex initMutex;
    std::condition_variable initCondition;
    std::atomic<bool> initialized{false};

    EventHandler *eventHandler;
    ApplicationState *appState;
    Interface *interface;
    KeyboardRepeatEngine *keyboardRepeatEngine;
};
```

### #5: Input translation

Is this internationalisation out of the window? Probably. Since Qt is running
in a separate thread, it can't receive Wayland events properly, it's completely
"headless" as it were. Therefore, every input event from Wayland is forwarded
to the Qt thread where it is translated into Qt events to be injected into the
Qt application. I believe this is supposed to be the job of QtWayland, which I
can't use here anyway (please [correct me][CONTACT] if I'm wrong about this).

```cpp
Qt::Key KeyboardHandler::xkbKeysymToQtKey(xkb_keysym_t keysym) {

    /* ... */

    switch (keysym) {
        case XKB_KEY_Escape:
            return Qt::Key_Escape;
        case XKB_KEY_Tab:
            return Qt::Key_Tab;
        case XKB_KEY_BackTab:
            return Qt::Key_Backtab;
        case XKB_KEY_BackSpace:
            return Qt::Key_Backspace;
        case XKB_KEY_Return:
            return Qt::Key_Return;
        case XKB_KEY_KP_Enter:
            return Qt::Key_Enter;
        case XKB_KEY_Insert:
            return Qt::Key_Insert;
        case XKB_KEY_Delete:
            return Qt::Key_Delete;
        case XKB_KEY_Pause:
            return Qt::Key_Pause;

        /* ... */

        default:
            return Qt::Key_unknown;
    }
}

Qt::KeyboardModifiers KeyboardHandler::xkbStateToQtModifiers() {
    Qt::KeyboardModifiers modifiers = Qt::NoModifier;

    if (!m_xkbState) {
        return modifiers;
    }

    if (xkb_state_mod_name_is_active(m_xkbState, XKB_MOD_NAME_SHIFT,
                                     XKB_STATE_MODS_EFFECTIVE)) {
        modifiers |= Qt::ShiftModifier;
    }
    if (xkb_state_mod_name_is_active(m_xkbState, XKB_MOD_NAME_CTRL,
                                     XKB_STATE_MODS_EFFECTIVE)) {
        modifiers |= Qt::ControlModifier;
    }
    if (xkb_state_mod_name_is_active(m_xkbState, XKB_MOD_NAME_ALT,
                                     XKB_STATE_MODS_EFFECTIVE)) {
        modifiers |= Qt::AltModifier;
    }
    if (xkb_state_mod_name_is_active(m_xkbState, XKB_MOD_NAME_LOGO,
                                     XKB_STATE_MODS_EFFECTIVE)) {
        modifiers |= Qt::MetaModifier;
    }

    return modifiers;
}
```

# tlockr: The Verdict

After a couple of months of development, it was mid-August and I had a thing I
felt was ready for me to actually use. I set it to run in place of Swaylock on
my laptop. First thing I do is close the laptop lid, putting it to sleep. I can
remember sitting on my bed while on holiday with a shitty Internet connection,
opening the laptop again, and seeing tlockr red-screen the session.

Minor detour while I explain what this actually is. When a screen locker uses
the `ext-session-lock` protocol, the compositor treats it a bit differently
from other Wayland clients. The client gains full, exclusive access to all
outputs and seats. It is the responsibility of the client to remove the lock
again before it exits, otherwise the compositor has no way of knowing whether
the locker actually performed any successful authentication, which is a
security problem. If a locker fails to do this before exiting, there's nothing
the compositor can do about it, so it is forced to prohibit all access to the
session. On Sway, this takes the form of an ominous red screen that you cannot
interact with at all, basically bricking your session. In other words, to get
back to normal you have to switch to a VT and kill your compositor, and all
other applications you started along with it.

I definitely lost some work that day. As it turns out I had forgotten to handle
cases where `epoll` returns `EINTR`, indicating an interrupted syscall, by the
suspend that occurred when I closed the laptop lid.

This problem painfully extended as well, if anything went wrong with tlockr,
you'd brick your compositor. This is exacerbated by the user-written QML. If
your QML had a syntax error, your session, along with all your work, was fucked.

In further experiments I attempted to implement some sort of built-in fallback
UI, which I never finished. Bear in mind that tlockr was nowhere complete at
this point, it only really had QML going for it, which was flawed anyway. I
think it was mid-October when I plugged in a keyboard while locked and, as you
probably guessed, lost yet another session to the red screen.

---

# nlock: Redemption

At this point, I reflected on the horror that was tlockr and, using the last
of my energy at this point, just went back to building what I actually wanted
in the first place.

To that one person who starred the tlockr GitHub repository, I'm sorry.

[nlock][nlock] was designed to be simpler. Quite a bit of the internal
architecture being inspired by Swaylock actually, but written in Rust instead.
Speaking of Rust, tlockr was basically the perfect exercise of how *not* to
write Rust, inadvertently making nlock much easier to write since I knew what
to *avoid* doing this time.

nlock uses Cairo for rendering, which it a hell of a lot simpler than
integrating Qt, and is designed in such a way that even if the renderer falls
to pieces, you can always unlock the locker. During tlockr development, I
did all my testing in a separate compositor instance to avoid the red screen
issue which would inevitably happen. After about a week of developing nlock,
I could already comfortably do this on my main compositor instance. Stability
clearly isn't much of an issue with nlock, on my compositor at least.

nlock is also quite customisable despite keeping the same core layout. Again,
this is thanks to the renderer stability, or rather, the stability of
everything around it. Playing with the renderer is very safe, the complete
opposite of tlockr.

Much of the shit from tlockr is also gone from nlock, especially the event
system, which now uses [mio][mio], but I'm experimenting with a bespoke one
that is more flexible with timers, and should hopefully allow nlock to run
on BSDs, most notably, FreeBSD. The main problem is that `TimerFd` is a Linux
kernel feature which nlock uses internally for key repetition. BSDs don't have
this, necessating the use of `kqueue` with `EVFILT_TIMER`. Unfortunately, I
can't find a nice abstraction that works with mio at the moment. nlock also
uses safe Rust almost entirely throughout, which avoids all FFI problems with
tlockr.

This is not to say nlock is perfect either, but it's been tested more thoroughly
than tlockr ever was, and I've used it every day for almost 4 months now with
no major issues. I'm personally not a fan of the way authentication is handled,
or how it communicates with the rest of the locker at the moment.

nlock achieves all the three original goals of the project, and is in a state
where I will probably make an initial release around the time this blog post
is published (give or take a few days).

---

# Lessons Learned

Some would say this is probably the most important section of this blog post.
I'm inclined to agree.

- Simpler is almost always better. tlockr failed because it tried to do too
    much. nlock was heavily scoped, achieving a better result.

- Think short-term first, long-term later. tlockr may have been better designed
    if I actually focused on what mattered first.

- Not really a "lesson", but writing Rust, event systems, and working with
    the Wayland protocol.

- ... and probably many more.

---

Well, that's it. Go check out [nlock][nlock] if you haven't already. As always
you can send any questions, suggestions, or even spelling mistakes (there are
always some) to the [usual places][CONTACT].

[where-is-my-sddm-theme]: https://github.com/stepanzubkov/where-is-my-sddm-theme
[swaylock]: https://github.com/swaywm/swaylock
[hyprlock]: https://github.com/hyprwm/hyprlock
[waylock]: https://codeberg.org/ifreund/waylock
[wlockr]: https://github.com/OldUser101/wlockr
[tlockr]: https://github.com/OldUser101/tlockr
[nlock]: https://github.com/OldUser101/nlock
[mio]: https://github.com/tokio-rs/mio
[CONTACT]: /contact/index.html
