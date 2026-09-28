// 비밀번호 규칙 — app/password_policy.py 와 같은 규칙. 서버가 최종 판단하고, 이 파일은 입력 중 안내용이다.
(function () {
  const MIN = 10, MAX = 64;
  const SEQUENCES = ["abcdefghijklmnopqrstuvwxyz", "0123456789", "qwertyuiop", "asdfghjkl", "zxcvbnm"];
  const COMMON = ["password", "passw0rd", "qwerty", "iloveyou", "admin", "welcome", "letmein",
    "footnote", "sunshine", "princess", "dragon", "monkey", "master", "login"];

  const RULES = [
    ["length", `${MIN}자 이상 ${MAX}자 이하`, (p) => p.length >= MIN && p.length <= MAX],
    ["letter", "영문 포함", (p) => /[A-Za-z]/.test(p)],
    ["digit", "숫자 포함", (p) => /[0-9]/.test(p)],
    ["special", "특수문자 포함 (예: ! @ # $ %)", (p) => /[^A-Za-z0-9\s]/.test(p)],
    ["no_space", "공백 없음", (p) => !/\s/.test(p)],
    ["no_repeat", "같은 문자 3번 이상 연속 금지 (예: aaa, 111)", (p) => !/(.)\1\1/.test(p)],
    ["no_sequence", "연속된 문자 4자리 이상 금지 (예: 1234, abcd, qwer)", (p) => !hasSequence(p)],
    ["no_email", "이메일 아이디 포함 금지", (p, email) => {
      const local = (email || "").split("@")[0].toLowerCase();
      return local.length < 3 || !p.toLowerCase().includes(local);
    }],
    ["no_common", "쉽게 추측되는 단어 금지 (예: password, qwerty)", (p) => !COMMON.some((w) => p.toLowerCase().includes(w))],
  ];

  function hasSequence(p) {
    const lowered = p.toLowerCase();
    for (const seq of SEQUENCES) {
      for (const text of [seq, [...seq].reverse().join("")]) {
        for (let i = 0; i + 4 <= text.length; i++) if (lowered.includes(text.slice(i, i + 4))) return true;
      }
    }
    return false;
  }

  /** 입력칸 아래에 체크리스트를 붙인다. getEmail은 이메일 아이디 규칙용(없으면 그 규칙은 서버가 판단). */
  function attach(input, getEmail) {
    const list = document.createElement("ul");
    list.className = "pw-rules";
    list.setAttribute("aria-live", "polite");
    const items = RULES.map(([code, label]) => {
      const li = document.createElement("li");
      li.dataset.code = code;
      li.textContent = label;
      list.append(li);
      return li;
    });
    input.insertAdjacentElement("afterend", list);

    function update() {
      const password = input.value;
      const email = getEmail ? getEmail() : "";
      let allOk = true;
      RULES.forEach(([code, , test], i) => {
        const li = items[i];
        if (code === "no_email" && !email) { li.hidden = true; return; }
        li.hidden = false;
        const ok = password.length > 0 && test(password, email);
        li.className = password.length === 0 ? "" : ok ? "ok" : "bad";
        if (!ok) allOk = false;
      });
      return allOk;
    }
    input.addEventListener("input", update);
    update();
    return { isValid: update, reset: () => { input.value = ""; update(); } };
  }

  /** 서버가 돌려준 weak_password 오류를 체크리스트에 반영한다. */
  function markServerProblems(input, problems) {
    const list = input.nextElementSibling;
    if (!list || !list.classList.contains("pw-rules")) return;
    for (const { code } of problems || []) {
      const li = list.querySelector(`[data-code="${code}"]`);
      if (li) { li.hidden = false; li.className = "bad"; }
    }
  }

  window.PasswordPolicy = { attach, markServerProblems };
})();
