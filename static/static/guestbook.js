function clearSubmitError() {
  const errElem = document.getElementById("submit-error");
  errElem.setAttribute("hidden", true);
}

function setSubmitError(err) {
  const errElem = document.getElementById("submit-error");
  errElem.innerText = `failed to submit: ${err}`;
  errElem.removeAttribute("hidden");
}

function clearSubmitSuccess() {
  const confElem = document.getElementById("submit-confirm");
  confElem.setAttribute("hidden", true);
}

function setSubmitSuccess() {
  const confElem = document.getElementById("submit-confirm");
  confElem.removeAttribute("hidden");
}

function clearSubmission() {
  const nameElem = document.getElementById("msg-name");
  const messageElem = document.getElementById("msg-message");

  nameElem.value = "";
  messageElem.value = "";
}

function submitMessage() {
  const nameElem = document.getElementById("msg-name");
  const messageElem = document.getElementById("msg-message");

  let name = nameElem.value;
  let message = messageElem.value;

  if (name.trim().length === 0 || name.length > 100) {
    throw "invalid name";
  }
  if (message.trim().length === 0 || message.length > 1000) {
    throw "invalid message";
  }

  const payload = {
    name: name,
    message: message,
  };

  fetch("https://guestbook.ngill.net/entries", {
    method: "POST",
    body: JSON.stringify(payload),
    headers: {
      "Content-Type": "application/json",
    },
  })
    .then((resp) => {
      if (!resp.ok) {
        return resp.text().then((err) => {
          throw err;
        });
      }
      setSubmitSuccess();
      clearSubmission();
    })
    .catch((err) => {
      setSubmitError(err);
    });
}

function setupGuestbook() {
  const submitElem = document.getElementById("msg-submit");
  submitElem.addEventListener("click", () => {
    clearSubmitSuccess();
    clearSubmitError();

    try {
      submitMessage();
    } catch (error) {
      setSubmitError(error);
    }
  });
}

function setFetchError(err) {
  const errElem = document.getElementById("fetch-error");
  errElem.innerText = `failed to fetch messages: ${err}`;
  errElem.removeAttribute("hidden");
}

function setNoMessages() {
  const noElem = document.getElementById("fetch-no-msgs");
  noElem.removeAttribute("hidden");
}

function clearMessages() {
  const msgElem = document.getElementById("messages");

  while (msgElem.firstChild) {
    msgElem.firstChild.remove();
  }
}

function addMessage(msg) {
  let msgRoot = document.getElementById("messages");

  let elem = document.createElement("div");
  elem.classList.add("message");

  let title = document.createElement("p");
  title.classList.add("message-name");
  title.textContent = msg.name;

  let message = document.createElement("p");
  message.classList.add("message-msg");
  message.textContent = msg.message;

  let date = document.createElement("p");
  date.classList.add("message-date");
  date.textContent = new Date(msg.ts * 1000).toISOString();

  elem.appendChild(title);
  elem.appendChild(message);
  elem.appendChild(date);

  msgRoot.appendChild(elem);
}

function updateGuestbook() {
  fetch("https://guestbook.ngill.net/entries")
    .then((resp) => {
      if (!resp.ok) {
        return resp.text().then((err) => {
          throw err;
        });
      }
      return resp.json();
    })
    .then((data) => {
      clearMessages();
      const msgs = data.reverse(); // we want newest first
      for (let i = 0; i < msgs.length; i++) {
        addMessage(msgs[i]);
      }
      if (msgs.length === 0) {
        setNoMessages();
      }
    })
    .catch((err) => {
      setFetchError(err);
    });
}

document.addEventListener("DOMContentLoaded", () => {
  setupGuestbook();
  clearSubmission();
  updateGuestbook();
});
