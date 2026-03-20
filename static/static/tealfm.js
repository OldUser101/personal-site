// Fetch Teal.fm playing status using Microcosm Slingshot

// Copyright (C) 2026, Nathan Gill
// Licensed under the MIT License
// See LICENSE_MIT for details.

const DID = "did:plc:khwj2pmtsiuijj4jnuomle37";
const COLLECTION = "fm.teal.alpha.actor.status";
const RKEY = "self";

// create an endpoint with the above DID, collection, and record key
function makeEndpoint() {
  return `https://slingshot.microcosm.blue/xrpc/com.atproto.repo.getRecord?repo=${DID}&collection=${COLLECTION}&rkey=${RKEY}`;
}

// set a class to indicate the current play status
function setPlaying(playing) {
  const statusElem = document.getElementById("playing-status");

  if (playing) {
    statusElem.classList.remove("not-playing");
    statusElem.classList.add("playing");
  } else {
    statusElem.classList.remove("playing");
    statusElem.classList.add("not-playing");
  }
}

// set the title of the currently playing track
function setPlayingStatusTitle(title, link) {
  const statusElem = document.getElementById("playing-status");

  let titleElem = document.getElementById("playing-status-title");
  if (titleElem) {
    titleElem.remove();
  }

  titleElem = document.createElement("a");
  titleElem.id = "playing-status-title";
  titleElem.textContent = title ? title : "Nothing playing right now!";

  if (link) {
    titleElem.setAttribute("href", link);
  } else {
    titleElem.removeAttribute("href");
  }

  statusElem.appendChild(titleElem);
}

// set the artists of the currently playing track
function setPlayingStatusArtists(artists) {
  const statusElem = document.getElementById("playing-status");

  let artistsElem = document.getElementById("playing-status-artists");
  if (artistsElem) {
    artistsElem.remove();
  }

  artistsElem = document.createElement("p");
  artistsElem.id = "playing-status-artists";
  artistsElem.textContent = artists.join(", ");

  statusElem.appendChild(artistsElem);
}

// clear the current play status
function clearPlayingStatus() {
  setPlaying(false);
  setPlayingStatusTitle("");
  setPlayingStatusArtists([]);
}

// fetch the current playing status and update DOM
function updatePlayingStatus() {
  fetch(makeEndpoint())
    .then((res) => res.json())
    .then((data) => {
      clearPlayingStatus();

      const status = data.value.item;

      if (!status) {
        console.error(`failed to fetch playing status, got: ${data}`);
        return;
      }

      let artistNames = [];
      for (let i = 0; i < status.artists.length; ++i) {
        let artistName = status.artists[i].artistName;
        if (artistName) {
          artistNames.push(artistName);
        }
      }

      if (!status.trackName || artistNames.length === 0) {
        // we probably aren't playing anything
        setPlaying(false);
        return;
      }

      setPlaying(true);
      setPlayingStatusTitle(status.trackName, status.originUrl);
      setPlayingStatusArtists(artistNames);
    })
    .catch((e) => console.error(`failed to fetch playing status: ${e}`));
}

// refresh play status on content load
document.addEventListener("DOMContentLoaded", () => {
  clearPlayingStatus();
  updatePlayingStatus();
});
