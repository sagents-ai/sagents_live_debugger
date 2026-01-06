# Making Events Use Browser Timezone in Phoenix LiveView

This document describes the challenge and working solution for detecting browser timezone and sending it to a Phoenix LiveView server, specifically for self-contained LiveView plugins that cannot modify the host application's JavaScript.

## The Problem

When building a LiveView dashboard (like a debugger), you want to display timestamps in the user's local timezone rather than UTC. This requires:

1. Detecting the browser's timezone (client-side JavaScript)
2. Sending that timezone to the LiveView server
3. Using it to format timestamps

The challenge is that **self-contained LiveView plugins cannot modify the host app's JavaScript**, which rules out the standard approach of passing timezone via LiveSocket connect params.

## Why This Is Hard

### Standard Approach (Not Available for Plugins)

Normally, you'd pass timezone in LiveSocket connect params:

```javascript
// In host app's app.js - NOT available for plugins
let liveSocket = new LiveSocket("/live", Socket, {
  params: {time_zone: Intl.DateTimeFormat().resolvedOptions().timeZone}
});
```

### Plugin Constraints

A self-contained LiveView plugin must:
- Work without modifying the host app's JavaScript
- Not require hook registration in the host app
- Use only inline JavaScript in templates

## Approaches That Don't Work

### 1. Phoenix LiveView Hooks

Hooks require registration in the host app's JavaScript:
```javascript
// Requires host app modification - NOT self-contained
let Hooks = { TimezoneHook: { mounted() { ... } } }
let liveSocket = new LiveSocket("/live", Socket, { hooks: Hooks })
```

**Result:** `unknown hook found for 'TimezoneHook'` error

### 2. Form with phx-change and Input Event

```html
<form phx-change="set_timezone">
  <input type="hidden" id="tz-input" name="timezone" value="UTC" />
</form>
<script>
  input.value = detectedTimezone;
  input.dispatchEvent(new Event('input', { bubbles: true }));
</script>
```

**Result:** Event not received by server. The `input` event on hidden inputs doesn't reliably trigger `phx-change`.

### 3. Form with phx-change and Change Event

Same as above but with `'change'` event instead of `'input'`.

**Result:** Still not received. Hidden inputs don't participate in form change detection the same way visible inputs do.

### 4. Window Events with phx-window-*

```html
<div phx-window-customtz="set_timezone"></div>
<script>
  window.dispatchEvent(new CustomEvent('customtz', {detail: {timezone: tz}}));
</script>
```

**Result:** Event not received. `phx-window-*` bindings may not work reliably with CustomEvents or have other constraints.

### 5. Direct JavaScript Event Dispatch Before LiveView Connected

```html
<script>
  // Runs immediately on page load
  dispatchTimezoneEvent();
</script>
```

**Result:** Event dispatched before LiveView WebSocket connected, so server never receives it.

### 6. setTimeout Delay

```javascript
setTimeout(() => dispatchTimezoneEvent(), 100);
```

**Result:** Unreliable. 100ms may not be enough, and longer delays create visible lag.

## The Working Solution

### Key Insight

Use a **hidden button with `phx-click`** and dynamically set `phx-value-*` attributes before programmatically clicking it. This works because:

1. `phx-click` is a core LiveView binding that reliably sends events
2. `phx-value-*` attributes are read at click time, so dynamic values work
3. `phx:page-loading-stop` event ensures LiveView is fully connected before clicking

### Implementation

#### 1. Hidden Button (Outside phx-update="ignore")

```html
<button id="sagents-tz-btn" phx-click="set_timezone" style="display: none;"></button>
```

The button must be **outside** any `phx-update="ignore"` container so LiveView can handle its events.

#### 2. Detection Script (Inside phx-update="ignore")

```html
<div phx-update="ignore" id="tz-script-container">
  <script>
    (function() {
      // Wait for LiveView to finish loading
      window.addEventListener('phx:page-loading-stop', function() {
        const tz = Intl.DateTimeFormat().resolvedOptions().timeZone || 'UTC';
        const btn = document.getElementById('sagents-tz-btn');
        if (btn) {
          btn.setAttribute('phx-value-timezone', tz);
          btn.click();
        }
      }, { once: true });
    })();
  </script>
</div>
```

The script is inside `phx-update="ignore"` to prevent re-execution on LiveView re-renders.

#### 3. Event Handler

```elixir
def handle_event("set_timezone", %{"timezone" => timezone}, socket) do
  case validate_timezone(timezone) do
    {:ok, validated_tz} ->
      {:noreply, assign(socket, :user_timezone, validated_tz)}
    {:error, _} ->
      {:noreply, socket}
  end
end

defp validate_timezone(timezone) when is_binary(timezone) do
  case DateTime.shift_zone(DateTime.utc_now(), timezone) do
    {:ok, _} -> {:ok, timezone}
    {:error, _} -> {:error, :invalid_timezone}
  end
end
```

#### 4. Timezone Database Configuration

The host app must have a timezone database configured:

```elixir
# config/config.exs
config :elixir, :time_zone_database, Tzdata.TimeZoneDatabase
```

And the dependency:
```elixir
# mix.exs
{:tzdata, "~> 1.1"}
```

#### 5. Using the Timezone

```elixir
defp format_timestamp(datetime, timezone) do
  case DateTime.shift_zone(datetime, timezone) do
    {:ok, shifted} ->
      shifted
      |> DateTime.truncate(:second)
      |> Calendar.strftime("%H:%M:%S %Z")
    {:error, _} ->
      datetime
      |> DateTime.truncate(:second)
      |> Calendar.strftime("%H:%M:%S UTC")
  end
end
```

## Critical Details

### Why phx:page-loading-stop?

This Phoenix LiveView event fires when:
- The initial page load completes
- LiveView WebSocket is connected
- The DOM is ready for interaction

Using `{ once: true }` ensures the listener only fires once.

### Why phx-update="ignore" for the Script?

Without this, LiveView would re-execute the script on every re-render, potentially sending the timezone event multiple times or at unexpected times.

### Why the Button Outside phx-update="ignore"?

Elements inside `phx-update="ignore"` have their events ignored by LiveView. The button must be outside so `phx-click` works.

### Why Validate the Timezone?

To prevent:
1. Invalid timezone strings from breaking `DateTime.shift_zone/2`
2. Potential injection attacks via malicious timezone values

## Summary

For self-contained LiveView plugins that need browser-side data:

1. Use a **hidden button with `phx-click`**
2. Set **`phx-value-*` attributes dynamically** before clicking
3. Wait for **`phx:page-loading-stop`** to ensure LiveView is connected
4. Keep the **button outside** and **script inside** `phx-update="ignore"`
5. Always **validate** client-provided data server-side
