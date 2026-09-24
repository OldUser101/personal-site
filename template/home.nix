cfg:
{
  lib,
}:
let
  content = ''
    <div style="text-align: center; margin-top: 1em;">
      <img src="/static/avatar.jpg" width="250" height="250" alt="My Profile Picture">

      <h1 style="font-size: 1.84rem; margin: 0;">Nathan Gill</h1>
      <h2 style="margin-top: 0; user-select: none;" id="uname" title="..in posix extended regex: _*[Oo]ld[Uu]ser(101)?">OldUser101</h2>

      <div style="padding-top: 1.5em; padding-bottom: 1.5em;">
        <p style="margin-bottom: 0;">
          Agender programmer who: writes code; breaks computers; and does other
          "cool things".
        </p>
        <p style="margin-top: 0;">Take a look for yourself.</p>
        <a href="/about/index.html">More about me &rarr;</a>
      </div>

      <div id="badges">
        <a class="badge" href="https://ngill.net">
          <img src="/static/gifs/badge.gif">
        </a>

        <a class="badge" href="https://aleaf.is-a.dev/" target="_blank" rel="noopener">
          <img src="https://aleaf.is-a.dev/aleaf-88x31.gif" alt="A leaf" width="88" height="31">
        </a>

        <div id="badges">
          <a class="badge" href="https://unixcore.sh" target="_blank" rel="noopener">
            <img src="/static/gifs/unixcore.gif">
          </a>

          <a class="badge" href="https://jj-vcs.dev" target="_blank" rel="noopener">
            <img src="/static/gifs/built_with_jj.gif">
          </a>

          <img class="badge" src="/static/gifs/gnu_linux.gif">

          <a class="badge" href="https://www.firefox.com" target="_blank" rel="noopener">
            <img src="/static/gifs/tested_on_firefox.gif">
          </a>
        </div>
      </div>

      <p style="margin-bottom: 0;"><strong>Other Sites</strong></p>
      <div>
        <a href="https://git.ngill.net">Personal Git Server</a>
      </div>
      <div>
        <a href="https://unixcore.sh/olduser">Unixcore Site</a>
      </div>
      <div>
        <a href="https://asmsim.ngill.net">AQA Assembly Language Simulator</a>
      </div>
      <div>
        <a href="https://mastermind.ngill.net">Mastermind Game</a>
      </div>
      <div style="margin-bottom: 1em;">
        <a href="https://archive.ngill.net">Site Archives</a>
      </div>
    </div>
  '';

  footer = ''
    <script>
      const USERNAMES = [
        "OldUser101",
        "___olduser101",
        "olduser",
        "olduser101",
        "___OldUser101",
      ];
      var CURRENT_USERNAME = 0;
    
      function updateUsername() {
        let next = Math.floor(Math.random() * USERNAMES.length);
        if (next == CURRENT_USERNAME) {
          next = (next + 1) % USERNAMES.length;
        }
        
        const userElem = document.getElementById("uname");
        userElem.innerText = USERNAMES[next];

        CURRENT_USERNAME = next;
      }

      document.addEventListener("DOMContentLoaded", () => {
        updateUsername();

        const userElem = document.getElementById("uname");
        userElem.addEventListener("click", () => {
          updateUsername();
        })
      })
    </script>
  '';
in
lib.buildPage {
  name = "home";
  text = lib.buildTemplateText (import ./page.nix cfg) {
    inherit content footer;
  };
}
