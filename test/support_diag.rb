# TEMP diagnostics for flaky collaborator picker tests — remove before merge.
module FlakeDiag
  JS = <<~JS
    window.__marker = Date.now(); window.__ev = [];
    const log = s => window.__ev.push(((performance.now()|0)) + "ms " + s);
    ["keydown","input","click","mousedown","focusin","focusout"].forEach(t =>
      document.addEventListener(t, e => log(t + ":" + (e.key||"") + ":" + (e.target.id || e.target.getAttribute?.("aria-label") || e.target.tagName) + ":" + (e.target.value ?? "")), true));
    ["turbo:load","turbo:visit","turbo:before-render","turbo:reload","pagehide","beforeunload"].forEach(t =>
      window.addEventListener(t, () => log(t), true));
    log("marker set, readyState=" + document.readyState + " navType=" + performance.getEntriesByType("navigation")[0]?.type);
  JS

  def visit(*)
    super
    execute_script(JS)
  end

  def before_teardown
    unless passed?
      info = evaluate_script(<<~JS) rescue $!.message
        (() => {
          const el = document.querySelector("[data-controller~='collaborator-select']");
          return {
            url: location.href, marker: window.__marker ?? null, readyState: document.readyState,
            hasFocus: document.hasFocus(), active: document.activeElement?.id || document.activeElement?.tagName,
            connected: !!(window.Stimulus && el && window.Stimulus.getControllerForElementAndIdentifier(el, "collaborator-select")),
            stimulus: !!window.Stimulus, navType: performance.getEntriesByType("navigation")[0]?.type,
            events: window.__ev ?? null
          }
        })()
      JS
      puts "\nDIAG #{name}: #{info.inspect}"
      logs = page.driver.browser.logs.get(:browser) rescue []
      puts "BROWSER LOG: #{logs.map(&:message).inspect}"
    end
    super
  end
end
ApplicationSystemTestCase.prepend(FlakeDiag)
