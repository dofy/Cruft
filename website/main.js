const LANGUAGE_PREFERENCE_KEY = "cruft.site.language";

// Remember which language page the visitor picked, so the auto-redirect below
// never overrides a deliberate choice.
for (const link of document.querySelectorAll(".lang-switch a")) {
  link.addEventListener("click", () => {
    try {
      localStorage.setItem(LANGUAGE_PREFERENCE_KEY, link.hreflang);
    } catch {
      // Private browsing or a blocked store: falling through just means the
      // visitor gets asked again next time, which is harmless.
    }
  });
}

// First visit to the English root from a Chinese browser: send them to the
// matching Chinese page once. Only from "/" — redirecting from a language page
// would fight the switcher.
if (location.pathname === "/" || location.pathname === "/index.html") {
  let stored = null;
  try {
    stored = localStorage.getItem(LANGUAGE_PREFERENCE_KEY);
  } catch {
    stored = null;
  }

  if (!stored) {
    const preferred = (navigator.languages ?? [navigator.language ?? ""]).find(
      (tag) => tag.toLowerCase().startsWith("zh"),
    );

    if (preferred) {
      const lower = preferred.toLowerCase();
      // Hant is signalled either by the script subtag or by a region that uses
      // Traditional Chinese. Everything else Chinese goes to Simplified.
      const isTraditional =
        lower.includes("hant") ||
        lower.includes("-tw") ||
        lower.includes("-hk") ||
        lower.includes("-mo");
      location.replace(isTraditional ? "/zh-Hant/" : "/zh-Hans/");
    }
  }
}

document.querySelector("#year").textContent = String(new Date().getFullYear());
