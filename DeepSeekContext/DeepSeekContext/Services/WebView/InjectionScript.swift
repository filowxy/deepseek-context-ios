import Foundation

/// JavaScript injected into chat.deepseek.com to bridge native Swift and the web page.
enum InjectionScript {
    static let source: String = """
    (function() {
        if (window.deepSeekContextBridge) { return; }
        window.deepSeekContextBridge = true;

        const NATIVE_HANDLER = 'deepSeekContext';
        const HEALTH_CHECK_SELECTOR = 'textarea[placeholder]';
        const SEND_SELECTOR = 'button[type="submit"]';
        const MESSAGE_CONTAINER_SELECTOR = '[data-testid="chat-message-list"], .chat-message-list, main';

        let consecutiveMissing = 0;
        const MAX_MISSING = 3;

        function postNative(type, payload) {
            if (window.webkit && window.webkit.messageHandlers && window.webkit.messageHandlers[NATIVE_HANDLER]) {
                window.webkit.messageHandlers[NATIVE_HANDLER].postMessage({ type: type, payload: payload });
            }
        }

        function findInput() {
            return document.querySelector('textarea');
        }

        function findSendButton() {
            return document.querySelector(SEND_SELECTOR);
        }

        function healthCheck() {
            const input = findInput();
            const send = findSendButton();
            const healthy = !!input && !!send;
            if (!healthy) {
                consecutiveMissing += 1;
            } else {
                consecutiveMissing = 0;
            }
            postNative('domHealth', { healthy: healthy && consecutiveMissing < MAX_MISSING, missingSelector: input ? (send ? null : SEND_SELECTOR) : HEALTH_CHECK_SELECTOR });
        }

        // Expose native-callable API to the page.
        window.DeepSeekContextNative = {
            setInput: function(text) {
                const input = findInput();
                if (!input) { postNative('error', 'input not found'); return false; }
                input.value = text;
                input.dispatchEvent(new Event('input', { bubbles: true }));
                return true;
            },
            appendInput: function(text) {
                const input = findInput();
                if (!input) { postNative('error', 'input not found'); return false; }
                input.value = (input.value ? input.value + '\\n' : '') + text;
                input.dispatchEvent(new Event('input', { bubbles: true }));
                return true;
            },
            injectSystem: function(text) {
                // ponytail: system message injection is simulated by prepending to the input.
                // Upgrade path: inject into conversation context when web API becomes available.
                return window.DeepSeekContextNative.appendInput(text);
            },
            clickSend: function() {
                const send = findSendButton();
                if (!send) { postNative('error', 'send button not found'); return false; }
                send.click();
                return true;
            },
            getInput: function() {
                const input = findInput();
                return input ? input.value : '';
            },
            getOutput: function() {
                // ponytail: naive last message extraction; refine selector per DeepSeek DOM.
                const container = document.querySelector(MESSAGE_CONTAINER_SELECTOR) || document.body;
                const messages = container.querySelectorAll('div');
                let last = '';
                messages.forEach(function(m) {
                    const text = m.innerText || '';
                    if (text.length > last.length) { last = text; }
                });
                return last;
            }
        };

        // Detect user sending a message.
        document.addEventListener('keydown', function(e) {
            if (e.key === 'Enter' && !e.shiftKey) {
                postNative('sendStarted', {});
            }
        }, true);

        // Observe final AI replies using a simple stability heuristic.
        (function observeReplies() {
            let lastText = '';
            let stabilityTimer = null;
            const container = document.querySelector(MESSAGE_CONTAINER_SELECTOR) || document.body;
            const observer = new MutationObserver(function() {
                const text = window.DeepSeekContextNative.getOutput();
                if (text === lastText) { return; }
                lastText = text;
                if (stabilityTimer) { clearTimeout(stabilityTimer); }
                stabilityTimer = setTimeout(function() {
                    postNative('finalReply', { text: text });
                }, 250);
            });
            observer.observe(container, { childList: true, subtree: true, characterData: true });
        })();

        // Initial health report.
        setTimeout(healthCheck, 1000);
        setInterval(healthCheck, 5000);

        postNative('log', { level: 'info', message: 'DeepSeek Context bridge initialized' });
    })();
    """
}
