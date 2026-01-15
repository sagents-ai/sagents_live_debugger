defmodule SagentsLiveDebugger.Layouts do
  use Phoenix.Component
  import Phoenix.HTML, only: [raw: 1]

  def app(assigns) do
    ~H"""
    <!DOCTYPE html>
    <html lang="en">
      <head>
        <meta charset="utf-8" />
        <meta name="viewport" content="width=device-width, initial-scale=1" />
        <title>Agent Debugger</title>

        <style>
          <%= raw(css()) %>
        </style>
      </head>
      <body>
        {@inner_content}
      </body>
    </html>
    """
  end

  defp css do
    """
    * { box-sizing: border-box; }
    body {
      margin: 0;
      padding: 0;
      font-family: -apple-system, BlinkMacSystemFont, "Segoe UI", Roboto, "Helvetica Neue", Arial, sans-serif;
      background: #ffffff;
      color: #1f2937;
      line-height: 1.5;
    }

    .container {
      max-width: 1280px;
      margin: 0 auto;
      padding: 2rem;
    }

    .header {
      display: flex;
      justify-content: space-between;
      align-items: center;
      margin-bottom: 2rem;
    }

    .header h1 {
      font-size: 1.875rem;
      font-weight: bold;
      margin: 0;
    }

    .refresh-indicator {
      display: flex;
      align-items: center;
      gap: 0.5rem;
      color: #10b981;
      font-size: 0.875rem;
    }

    .refresh-indicator .spinner {
      font-size: 1.125rem;
      animation: spin 2s linear infinite;
    }

    @keyframes spin {
      from { transform: rotate(0deg); }
      to { transform: rotate(360deg); }
    }

    .overview {
      margin-bottom: 2rem;
    }

    .overview h2 {
      font-size: 1.125rem;
      font-weight: 600;
      margin-bottom: 1rem;
    }

    .metrics-grid {
      display: grid;
      grid-template-columns: repeat(auto-fit, minmax(200px, 1fr));
      gap: 1rem;
    }

    .metric-card {
      background: #f9fafb;
      border: 1px solid #e5e7eb;
      border-radius: 0.5rem;
      padding: 1rem;
      text-align: center;
    }

    .metric-value {
      font-size: 1.5rem;
      font-weight: 600;
      margin-bottom: 0.5rem;
    }

    .metric-label {
      font-size: 0.875rem;
      color: #6b7280;
    }

    .filters {
      display: flex;
      flex-wrap: wrap;
      gap: 1rem;
      margin-bottom: 1.5rem;
      padding: 1rem;
      background: #f9fafb;
      border-radius: 0.5rem;
    }

    .filter-group {
      display: flex;
      flex-direction: column;
      gap: 0.25rem;
    }

    .filter-group.search {
      flex: 1;
      min-width: 200px;
    }

    .filter-label {
      font-size: 0.75rem;
      font-weight: 600;
      color: #6b7280;
      text-transform: uppercase;
    }

    .filter-select,
    .filter-input {
      padding: 0.5rem 0.75rem;
      border: 1px solid #d1d5db;
      border-radius: 0.25rem;
      font-size: 0.875rem;
      background: white;
    }

    .filter-select:focus,
    .filter-input:focus {
      outline: none;
      ring: 2px;
      ring-color: #3b82f6;
    }

    .table-container {
      background: white;
      border: 1px solid #e5e7eb;
      border-radius: 0.5rem;
      overflow: hidden;
    }

    table {
      width: 100%;
      border-collapse: collapse;
    }

    thead {
      background: #f9fafb;
    }

    th {
      text-align: left;
      padding: 0.75rem 1rem;
      font-size: 0.875rem;
      font-weight: 600;
      color: #374151;
      border-bottom: 2px solid #e5e7eb;
    }

    tbody tr {
      border-bottom: 1px solid #e5e7eb;
      transition: background-color 0.15s;
    }

    tbody tr:hover {
      background: #f9fafb;
    }

    td {
      padding: 1rem;
    }

    .conv-id {
      display: flex;
      align-items: center;
      gap: 0.5rem;
      font-weight: 500;
    }

    .conv-id-icon {
      font-size: 1.25rem;
    }

    .agent-id {
      margin-top: 0.25rem;
      font-size: 0.875rem;
      color: #6b7280;
    }

    .status-badge {
      display: inline-block;
      padding: 0.25rem 0.75rem;
      border-radius: 9999px;
      font-size: 0.75rem;
      font-weight: 600;
      background: #dbeafe;
      color: #1e40af;
    }

    .status-desc {
      margin-top: 0.25rem;
      font-size: 0.875rem;
      color: #6b7280;
    }

    .viewer-count {
      font-size: 1rem;
    }

    .text-gray {
      color: #6b7280;
      font-size: 0.875rem;
    }

    .text-muted {
      color: #9ca3af;
    }

    .btn {
      padding: 0.5rem 1rem;
      border-radius: 0.25rem;
      font-size: 0.875rem;
      border: none;
      cursor: pointer;
    }

    .btn-disabled {
      background: #d1d5db;
      color: #6b7280;
      cursor: not-allowed;
    }

    .empty-state {
      text-align: center;
      padding: 3rem;
      color: #6b7280;
    }

    /* Agent Detail View Styles */
    .agent-detail-container {
      padding: 2rem;
      max-width: 1400px;
      margin: 0 auto;
    }

    .agent-detail-header {
      display: flex;
      justify-content: space-between;
      align-items: center;
      margin-bottom: 2rem;
      padding-bottom: 1rem;
      border-bottom: 2px solid #e5e7eb;
    }

    .agent-detail-header h2 {
      margin: 0;
      font-size: 1.5rem;
      color: #1f2937;
    }

    .btn-back {
      padding: 0.5rem 1rem;
      background: #6366f1;
      color: white;
      text-decoration: none;
      border-radius: 0.375rem;
      font-weight: 500;
      transition: background 0.2s;
    }

    .btn-back:hover {
      background: #4f46e5;
    }

    .auto-refresh {
      color: #6b7280;
      font-size: 0.875rem;
    }

    /* Tabs */
    .agent-detail-tabs {
      display: flex;
      gap: 0.5rem;
      margin-bottom: 2rem;
      border-bottom: 2px solid #e5e7eb;
    }

    .tab-button {
      padding: 0.75rem 1.5rem;
      background: none;
      border: none;
      border-bottom: 2px solid transparent;
      margin-bottom: -2px;
      cursor: pointer;
      font-weight: 500;
      color: #6b7280;
      transition: all 0.2s;
    }

    .tab-button:hover {
      color: #1f2937;
    }

    .tab-button.active {
      color: #6366f1;
      border-bottom-color: #6366f1;
    }

    /* Info Sections */
    .info-section {
      margin-bottom: 2rem;
    }

    .info-section h3 {
      font-size: 1.25rem;
      margin-bottom: 1rem;
      color: #1f2937;
    }

    .info-card {
      background: white;
      border: 1px solid #e5e7eb;
      border-radius: 0.5rem;
      padding: 1.5rem;
    }

    .info-row {
      display: flex;
      padding: 0.75rem 0;
      border-bottom: 1px solid #f3f4f6;
    }

    .info-row:last-child {
      border-bottom: none;
    }

    .info-label {
      font-weight: 600;
      color: #6b7280;
      min-width: 180px;
    }

    .info-value {
      color: #1f2937;
      flex: 1;
    }

    /* List Cards */
    .list-card {
      background: white;
      border: 1px solid #e5e7eb;
      border-radius: 0.5rem;
    }

    .list-item {
      padding: 1rem 1.5rem;
      border-bottom: 1px solid #f3f4f6;
    }

    .list-item:last-child {
      border-bottom: none;
    }

    .list-item-header {
      display: flex;
      justify-content: space-between;
      align-items: center;
    }

    .list-item-name {
      font-weight: 600;
      color: #1f2937;
      font-size: 1rem;
    }

    .list-item-module {
      font-family: 'Courier New', monospace;
      font-size: 0.875rem;
      color: #6b7280;
    }

    .list-item-description {
      color: #6b7280;
      margin-top: 0.5rem;
      margin-bottom: 0.5rem;
    }

    .list-item-details {
      margin-top: 0.75rem;
      padding: 0.75rem;
      background: #f9fafb;
      border-radius: 0.375rem;
      font-size: 0.875rem;
    }

    .list-item-details pre {
      margin: 0.5rem 0 0 0;
      padding: 0.5rem;
      background: white;
      border: 1px solid #e5e7eb;
      border-radius: 0.25rem;
      overflow-x: auto;
      font-size: 0.75rem;
    }

    .list-item-details ul {
      margin: 0.5rem 0 0 1.5rem;
    }

    .list-item-details li {
      margin: 0.25rem 0;
    }

    .list-item-details code {
      background: #f3f4f6;
      padding: 0.125rem 0.375rem;
      border-radius: 0.25rem;
      font-family: 'Courier New', monospace;
    }

    /* Badges */
    .badge {
      display: inline-block;
      padding: 0.125rem 0.5rem;
      border-radius: 0.25rem;
      font-size: 0.75rem;
      font-weight: 600;
      margin-left: 0.5rem;
    }

    .badge-async {
      background: #dbeafe;
      color: #1e40af;
    }

    .badge-required {
      background: #fee2e2;
      color: #991b1b;
    }

    /* Messages Tab */
    .messages-tab {
      padding: 0;
    }

    .messages-header {
      margin-bottom: 1rem;
    }

    .messages-header h3 {
      font-size: 1.25rem;
      color: #1f2937;
    }

    .messages-list {
      display: flex;
      flex-direction: column;
      gap: 1rem;
    }

    /* Message Items */
    .message-item {
      background: white;
      border: 2px solid #e5e7eb;
      border-radius: 0.5rem;
      padding: 1rem;
    }

    .message-system {
      border-left: 4px solid #dc2626;
      background: #fef2f2;
    }

    .message-user {
      border-left: 4px solid #3b82f6;
    }

    .message-assistant {
      border-left: 4px solid #10b981;
    }

    .message-tool {
      border-left: 4px solid #f59e0b;
    }

    .message-header {
      display: flex;
      gap: 1rem;
      align-items: center;
      margin-bottom: 0.75rem;
      padding-bottom: 0.5rem;
      border-bottom: 1px solid #f3f4f6;
    }

    .message-role {
      font-weight: 600;
      color: #1f2937;
    }

    .message-index {
      font-size: 0.875rem;
      color: #6b7280;
      font-family: 'Courier New', monospace;
    }

    .message-status {
      padding: 0.125rem 0.5rem;
      border-radius: 0.25rem;
      font-size: 0.75rem;
      font-weight: 600;
    }

    .message-status.status-complete {
      background: #d1fae5;
      color: #065f46;
    }

    .message-status.status-cancelled {
      background: #fee2e2;
      color: #991b1b;
    }

    .message-content {
      margin-bottom: 0.75rem;
      color: #1f2937;
      line-height: 1.6;
    }

    .formatted-content {
      white-space: pre-wrap;
    }

    .multimodal-content {
      display: flex;
      flex-direction: column;
      gap: 0.5rem;
    }

    .content-part-text {
      /* whitespace handling from .formatted-content */
    }

    .content-part-image,
    .content-part-unknown {
      padding: 0.5rem;
      background: #f3f4f6;
      border-radius: 0.25rem;
      font-family: 'Courier New', monospace;
      font-size: 0.875rem;
    }

    /* Thinking Content */
    .content-part-thinking {
      border: 1px solid #e5e7eb;
      border-radius: 0.375rem;
      background: #fafafa;
    }

    .thinking-header {
      cursor: pointer;
      padding: 0.5rem 0.75rem;
      background: #f3f4f6;
      border-bottom: 1px solid #e5e7eb;
      display: flex;
      justify-content: space-between;
      align-items: center;
      user-select: none;
      transition: background 0.2s;
    }

    .thinking-header:hover {
      background: #e5e7eb;
    }

    .thinking-label {
      font-size: 0.8125rem;
      color: #6b7280;
      font-weight: 500;
    }

    .thinking-content-wrapper {
      background: #fafafa;
    }

    .thinking-content {
      padding: 0.75rem;
      color: #6b7280;
      line-height: 1.6;
      font-family: -apple-system, BlinkMacSystemFont, "Segoe UI", Roboto, "Helvetica Neue", Arial, sans-serif;
      font-size: 0.8125rem;
      max-height: 400px;
      overflow-y: auto;
    }

    /* Scrollbar styling for thinking content */
    .thinking-content::-webkit-scrollbar {
      width: 6px;
    }

    .thinking-content::-webkit-scrollbar-track {
      background: #f3f4f6;
      border-radius: 3px;
    }

    .thinking-content::-webkit-scrollbar-thumb {
      background: #d1d5db;
      border-radius: 3px;
    }

    .thinking-content::-webkit-scrollbar-thumb:hover {
      background: #9ca3af;
    }

    /* Tool Calls */
    .message-tool-calls,
    .message-tool-results {
      margin-top: 0.75rem;
      padding: 0.75rem;
      background: #f9fafb;
      border-radius: 0.375rem;
    }

    .message-tool-calls strong,
    .message-tool-results strong {
      display: block;
      margin-bottom: 0.5rem;
      color: #374151;
    }

    .tool-call,
    .tool-result {
      margin: 0.5rem 0;
      padding: 0.75rem;
      background: white;
      border: 1px solid #e5e7eb;
      border-radius: 0.375rem;
    }

    .tool-call-header,
    .tool-result-header {
      display: flex;
      justify-content: space-between;
      align-items: center;
      margin-bottom: 0.5rem;
    }

    .tool-name {
      font-weight: 600;
      color: #1f2937;
    }

    .tool-call-id {
      font-family: 'Courier New', monospace;
      font-size: 0.75rem;
      color: #6b7280;
      background: #f3f4f6;
      padding: 0.125rem 0.375rem;
      border-radius: 0.25rem;
    }

    .tool-arguments,
    .tool-result-content {
      margin-top: 0.5rem;
    }

    .tool-arguments strong {
      font-size: 0.875rem;
      color: #6b7280;
    }

    .tool-arguments pre,
    .tool-result-content pre {
      margin: 0.25rem 0 0 0;
      padding: 0.5rem;
      background: #f3f4f6;
      border-radius: 0.25rem;
      overflow-x: auto;
      font-size: 0.875rem;
      line-height: 1.5;
    }

    .result-status {
      padding: 0.125rem 0.5rem;
      border-radius: 0.25rem;
      font-size: 0.75rem;
      font-weight: 600;
    }

    .result-status.status-success {
      background: #d1fae5;
      color: #065f46;
    }

    .result-status.status-error {
      background: #fee2e2;
      color: #991b1b;
    }

    /* Message Metadata */
    .message-metadata {
      margin-top: 0.75rem;
      padding: 0.5rem;
      background: #f9fafb;
      border-radius: 0.375rem;
    }

    .message-metadata summary {
      cursor: pointer;
      font-weight: 600;
      color: #6b7280;
      font-size: 0.875rem;
    }

    .message-metadata pre {
      margin: 0.5rem 0 0 0;
      padding: 0.5rem;
      background: white;
      border: 1px solid #e5e7eb;
      border-radius: 0.25rem;
      overflow-x: auto;
      font-size: 0.75rem;
    }

    /* Not Found */
    .agent-not-found {
      padding: 3rem;
      text-align: center;
    }

    .agent-not-found h2 {
      color: #1f2937;
      margin-bottom: 1rem;
    }

    .agent-not-found p {
      color: #6b7280;
      margin-bottom: 2rem;
    }

    .loading {
      padding: 2rem;
      text-align: center;
      color: #6b7280;
    }

    .btn-view {
      padding: 0.375rem 0.75rem;
      background: #6366f1;
      color: white;
      text-decoration: none;
      border-radius: 0.375rem;
      font-weight: 500;
      transition: background 0.2s;
      display: inline-block;
    }

    .btn-view:hover {
      background: #4f46e5;
    }

    /* System Message Sections */
    .system-messages-container {
      margin-bottom: 2rem;
    }

    .system-message-section {
      margin-bottom: 1rem;
    }

    .system-message-card {
      background: white;
      border: 2px solid #6366f1;
      border-radius: 0.5rem;
      overflow: hidden;
    }

    .system-message-card.base-prompt {
      border-color: #ec4899;
    }

    .system-message-header {
      cursor: pointer;
      padding: 1rem 1.5rem;
      background: #f9fafb;
      color: #1f2937;
      font-weight: 600;
      display: flex;
      justify-content: space-between;
      align-items: center;
      user-select: none;
      transition: background 0.2s;
      border-bottom: 1px solid #e5e7eb;
    }

    .system-message-header:hover {
      background: #f3f4f6;
    }

    .system-message-title {
      display: flex;
      align-items: center;
      gap: 0.75rem;
      font-size: 1rem;
    }

    .system-message-icon {
      font-size: 1.125rem;
    }

    .system-message-badge {
      font-size: 0.75rem;
      background: #e0e7ff;
      color: #4338ca;
      padding: 0.25rem 0.75rem;
      border-radius: 1rem;
      font-weight: 500;
    }

    .system-message-card.base-prompt .system-message-badge {
      background: #fce7f3;
      color: #9f1239;
    }

    .toggle-icon {
      font-size: 0.875rem;
      transition: transform 0.2s;
      font-family: monospace;
      color: #6b7280;
    }

    .toggle-icon.collapsed::before {
      content: '▶';
    }

    .toggle-icon:not(.collapsed)::before {
      content: '▼';
    }

    .system-message-content-wrapper {
      background: white;
    }

    .system-message-content {
      padding: 1.5rem;
      background: #fafafa;
      color: #1f2937;
      line-height: 1.7;
      font-family: -apple-system, BlinkMacSystemFont, "Segoe UI", Roboto, "Helvetica Neue", Arial, sans-serif;
      font-size: 0.9375rem;
      max-height: 500px;
      overflow-y: auto;
      margin: 1rem 1.5rem;
      margin-bottom: 0.5rem;
      border-radius: 0.375rem;
      border: 1px solid #e5e7eb;
    }

    .system-message-info {
      padding: 0 1.5rem;
      padding-bottom: 1.5rem;
      color: #6b7280;
      font-size: 0.875rem;
    }

    .system-message-info small {
      display: block;
      line-height: 1.5;
    }

    /* Scrollbar styling for system message content */
    .system-message-content::-webkit-scrollbar {
      width: 8px;
    }

    .system-message-content::-webkit-scrollbar-track {
      background: #f3f4f6;
      border-radius: 4px;
    }

    .system-message-content::-webkit-scrollbar-thumb {
      background: #d1d5db;
      border-radius: 4px;
    }

    .system-message-content::-webkit-scrollbar-thumb:hover {
      background: #9ca3af;
    }

    /* Middleware Configuration Display */
    .middleware-header-clickable {
      cursor: pointer;
      user-select: none;
      transition: background 0.2s;
    }

    .middleware-header-clickable:hover {
      background: #f9fafb;
    }

    .middleware-content {
      padding-top: 0.75rem;
    }

    .middleware-config {
      margin-top: 0.5rem;
      display: flex;
      flex-direction: column;
      gap: 1rem;
    }

    .config-entry {
      padding: 0.75rem;
      background: #f9fafb;
      border-radius: 0.375rem;
      border: 1px solid #e5e7eb;
    }

    .config-label {
      font-weight: 600;
      color: #374151;
      font-size: 0.875rem;
      margin-bottom: 0.5rem;
    }

    .config-value {
      margin: 0;
      padding: 0.75rem;
      background: white;
      border: 1px solid #e5e7eb;
      border-radius: 0.25rem;
      overflow-x: auto;
      font-family: 'Courier New', monospace;
      font-size: 0.8125rem;
      color: #1f2937;
      line-height: 1.5;
    }

    .config-value-text {
      white-space: pre-wrap;
      word-wrap: break-word;
    }

    /* Middleware Model Section */
    .middleware-model {
      margin-top: 0.75rem;
      border: 1px solid #e5e7eb;
      border-radius: 0.375rem;
      background: #fafafa;
    }

    .middleware-model-header {
      cursor: pointer;
      padding: 0.75rem 1rem;
      background: #f3f4f6;
      border-bottom: 1px solid #e5e7eb;
      display: flex;
      justify-content: space-between;
      align-items: center;
      gap: 1rem;
      user-select: none;
      transition: background 0.2s;
    }

    .middleware-model-header:hover {
      background: #e5e7eb;
    }

    .middleware-model-header .config-label {
      margin: 0;
      font-size: 0.875rem;
      flex-shrink: 0;
    }

    .model-brief {
      flex: 1;
      color: #6b7280;
      font-size: 0.8125rem;
      font-family: 'Courier New', monospace;
      white-space: nowrap;
      overflow: hidden;
      text-overflow: ellipsis;
    }

    .middleware-model-content {
      background: #fafafa;
      padding: 1rem;
    }

    .middleware-model-content .config-value {
      max-height: 400px;
      overflow-y: auto;
    }

    /* Scrollbar styling for model content */
    .middleware-model-content .config-value::-webkit-scrollbar {
      width: 6px;
      height: 6px;
    }

    .middleware-model-content .config-value::-webkit-scrollbar-track {
      background: #f3f4f6;
      border-radius: 3px;
    }

    .middleware-model-content .config-value::-webkit-scrollbar-thumb {
      background: #d1d5db;
      border-radius: 3px;
    }

    .middleware-model-content .config-value::-webkit-scrollbar-thumb:hover {
      background: #9ca3af;
    }

    /* Events Tab Styles */
    .events-tab {
      padding: 20px;
    }

    .events-header {
      margin-bottom: 20px;
    }

    .events-header h3 {
      margin: 0 0 5px 0;
      font-size: 1.2rem;
    }

    .events-subtitle {
      margin: 0;
      color: #6b7280;
      font-size: 0.9rem;
    }

    .events-list {
      display: flex;
      flex-direction: column;
      gap: 8px;
    }

    .event-item {
      background: white;
      border-radius: 6px;
      overflow: hidden;
      border: 1px solid #e5e7eb;
    }

    .event-item-header {
      display: flex;
      justify-content: space-between;
      align-items: center;
      padding: 12px 16px;
      cursor: pointer;
      transition: background 0.2s;
    }

    .event-item-header:hover {
      background: #f9fafb;
    }

    .event-item-main {
      display: flex;
      align-items: center;
      gap: 12px;
      flex: 1;
    }

    .event-badge {
      display: inline-block;
      padding: 4px 8px;
      border-radius: 4px;
      font-size: 0.75rem;
      font-weight: 600;
      text-transform: uppercase;
      letter-spacing: 0.5px;
    }

    .event-badge-regular {
      background: #3b82f6;
      color: white;
    }

    .event-badge-std {
      background: #3b82f6;
      color: white;
    }

    .event-badge-debug {
      background: #8b5cf6;
      color: white;
    }

    .event-badge-dbg {
      background: #8b5cf6;
      color: white;
    }

    .event-summary {
      font-size: 0.95rem;
      color: #1f2937;
    }

    .event-field-inline {
      display: inline-flex;
      gap: 8px;
      margin-left: 8px;
      font-size: 0.85rem;
      font-family: monospace;
    }

    .token-input {
      color: #3b82f6;  /* Blue for input (tokens sent to LLM) */
      font-weight: 500;
    }

    .token-output {
      color: #a855f7;  /* Purple for output (tokens received from LLM) */
      font-weight: 500;
    }

    .event-item-meta {
      display: flex;
      align-items: center;
      gap: 12px;
    }

    .event-timestamp {
      font-size: 0.85rem;
      color: #6b7280;
      font-family: monospace;
    }

    .event-details {
      border-top: 1px solid #e5e7eb;
      background: #fafafa;
    }

    .event-details-content {
      padding: 16px;
      display: flex;
      flex-direction: column;
      gap: 12px;
    }

    .event-field {
      display: flex;
      gap: 8px;
    }

    .event-label {
      font-weight: 600;
      color: #6b7280;
      min-width: 140px;
    }

    .event-value {
      color: #1f2937;
      word-break: break-word;
    }

    .event-raw {
      background: #f3f4f6;
      border: 1px solid #e5e7eb;
      border-radius: 4px;
      padding: 12px;
      font-size: 0.85rem;
      overflow-x: auto;
      margin: 0;
      color: #374151;
    }

    /* TODOs Tab Styles */
    .todos-tab {
      padding: 20px;
    }

    .todos-header {
      display: flex;
      align-items: center;
      gap: 12px;
      margin-bottom: 20px;
    }

    .todos-header h3 {
      margin: 0;
      font-size: 1.2rem;
    }

    .todos-count-badge {
      display: inline-block;
      padding: 4px 10px;
      background: #f3f4f6;
      color: #1f2937;
      border-radius: 12px;
      font-size: 0.85rem;
      font-weight: 600;
    }

    .tab-count-badge {
      display: inline-block;
      margin-left: 6px;
      padding: 2px 8px;
      background: #3b82f6;
      color: white;
      border-radius: 10px;
      font-size: 0.75rem;
      font-weight: 600;
    }

    .todos-list {
      display: flex;
      flex-direction: column;
      gap: 12px;
    }

    .todo-item {
      background: white;
      border-left: 4px solid;
      border-radius: 6px;
      padding: 16px;
      border: 1px solid #e5e7eb;
    }

    /* Status-based border colors */
    .todo-status-pending {
      border-left-color: #6b7280;
    }

    .todo-status-in_progress {
      border-left-color: #3b82f6;
      background: rgba(59, 130, 246, 0.05);
      box-shadow: 0 0 0 1px rgba(59, 130, 246, 0.1);
    }

    .todo-status-completed {
      border-left-color: #10b981;
      opacity: 0.7;
    }

    .todo-header {
      display: flex;
      justify-content: space-between;
      align-items: center;
      margin-bottom: 10px;
    }

    .todo-header-left {
      display: flex;
      align-items: center;
      gap: 8px;
    }

    .todo-number {
      font-weight: 600;
      color: #6b7280;
      font-size: 0.85rem;
      min-width: 30px;
    }

    .todo-icon {
      font-size: 1.1rem;
    }

    .todo-badge {
      padding: 4px 10px;
      border-radius: 4px;
      font-size: 0.75rem;
      font-weight: 600;
      letter-spacing: 0.5px;
    }

    .todo-badge.status-pending {
      background: #374151;
      color: #ffffffee;
    }

    .todo-badge.status-in_progress {
      background: #1e40af;
      color: #ffffffee;
    }

    .todo-badge.status-completed {
      background: #065f46;
      color: #ffffffee;
    }

    .todo-content {
      font-size: 0.95rem;
      line-height: 1.5;
      color: #1f2937;
      margin-bottom: 8px;
    }

    .todo-active-form {
      display: flex;
      align-items: center;
      gap: 6px;
      margin-top: 8px;
      padding-top: 8px;
      border-top: 1px solid #e5e7eb;
      font-size: 0.9rem;
      color: #6b7280;
    }

    .active-form-label {
      font-weight: 600;
    }

    .todo-active-form em {
      color: #4b5563;
    }

    /* Auto-Follow Header Styles */
    .header {
      flex-direction: column;
      align-items: flex-start;
      gap: 0.75rem;
    }

    .header-row {
      display: flex;
      width: 100%;
      justify-content: space-between;
      align-items: center;
    }

    .auto-follow-toggle {
      display: flex;
      align-items: center;
      gap: 0.5rem;
      cursor: pointer;
      font-size: 0.875rem;
      color: #6b7280;
    }

    .auto-follow-toggle input[type="checkbox"] {
      cursor: pointer;
    }

    .followed-indicator {
      display: flex;
      align-items: center;
      gap: 0.75rem;
      padding: 0.5rem 1rem;
      background: #fef3c7;
      border: 1px solid #fcd34d;
      border-radius: 0.5rem;
    }

    .btn-following-toggle {
      display: inline-flex;
      align-items: center;
      gap: 0.375rem;
      padding: 0.375rem 0.75rem;
      background: #10b981;
      color: white;
      border: none;
      border-radius: 0.375rem;
      font-size: 0.875rem;
      font-weight: 500;
      cursor: pointer;
      transition: background 0.2s;
    }

    .btn-following-toggle:hover {
      background: #dc2626;
    }

    .followed-agent-link {
      color: #4f46e5;
      font-weight: 600;
      font-family: 'Courier New', monospace;
      font-size: 0.875rem;
      text-decoration: none;
      padding: 0.25rem 0.5rem;
      background: white;
      border-radius: 0.25rem;
      border: 1px solid #e5e7eb;
      transition: all 0.2s;
    }

    .followed-agent-link:hover {
      color: #3730a3;
      background: #eef2ff;
      border-color: #a5b4fc;
      text-decoration: underline;
    }

    .followed-badge {
      font-size: 1rem;
      margin-left: 0.25rem;
    }

    .followed-row {
      background: #fefce8 !important;
    }

    .followed-row:hover {
      background: #fef9c3 !important;
    }

    /* Follow/Unfollow buttons in table */
    .btn-follow {
      padding: 0.375rem 0.75rem;
      background: #6366f1;
      color: white;
      border: none;
      border-radius: 0.375rem;
      font-size: 0.875rem;
      font-weight: 500;
      cursor: pointer;
      transition: background 0.2s;
    }

    .btn-follow:hover {
      background: #4f46e5;
    }

    .btn-unfollow {
      padding: 0.375rem 0.75rem;
      background: #ef4444;
      color: white;
      border: none;
      border-radius: 0.375rem;
      font-size: 0.875rem;
      font-weight: 500;
      cursor: pointer;
      transition: background 0.2s;
    }

    .btn-unfollow:hover {
      background: #dc2626;
    }

    .actions-cell {
      display: flex;
      gap: 0.5rem;
    }

    /* Sub-Agents Tab Styles */
    .subagents-container {
      padding: 1rem;
    }

    .subagents-list {
      display: flex;
      flex-direction: column;
      gap: 0.75rem;
    }

    .subagent-entry {
      border: 1px solid #e5e7eb;
      border-radius: 0.5rem;
      background: #f9fafb;
      overflow: hidden;
    }

    /* Status-based left border colors */
    .subagent-entry.status-starting {
      border-left: 4px solid #f59e0b;
    }

    .subagent-entry.status-running {
      border-left: 4px solid #3b82f6;
    }

    .subagent-entry.status-completed {
      border-left: 4px solid #10b981;
    }

    .subagent-entry.status-interrupted {
      border-left: 4px solid #f59e0b;
    }

    .subagent-entry.status-error {
      border-left: 4px solid #ef4444;
    }

    .subagent-header {
      display: flex;
      align-items: center;
      gap: 0.75rem;
      padding: 0.75rem 1rem;
      cursor: pointer;
      transition: background 0.15s;
    }

    .subagent-header:hover {
      background: #f3f4f6;
    }

    .subagent-expand-icon {
      font-size: 0.75rem;
      color: #6b7280;
      width: 1rem;
      flex-shrink: 0;
    }

    .subagent-name {
      font-weight: 500;
      color: #1f2937;
      flex: 1;
    }

    /* Sub-agent status badges */
    .subagent-status-badge {
      display: inline-block;
      padding: 0.125rem 0.5rem;
      border-radius: 0.25rem;
      font-size: 0.75rem;
      font-weight: 600;
    }

    .subagent-status-badge.status-starting {
      background: #fef3c7;
      color: #92400e;
    }

    .subagent-status-badge.status-running {
      background: #dbeafe;
      color: #1e40af;
    }

    .subagent-status-badge.status-completed {
      background: #d1fae5;
      color: #065f46;
    }

    .subagent-status-badge.status-interrupted {
      background: #fef3c7;
      color: #92400e;
    }

    .subagent-status-badge.status-error {
      background: #fee2e2;
      color: #991b1b;
    }

    /* Token usage badge */
    .subagent-token-badge {
      display: inline-block;
      padding: 0.125rem 0.5rem;
      border-radius: 0.25rem;
      font-size: 0.75rem;
      background: #f3f4f6;
      color: #374151;
      border: 1px solid #d1d5db;
    }

    .subagent-duration {
      font-size: 0.875rem;
      color: #6b7280;
    }

    .subagent-message-count {
      font-size: 0.875rem;
      color: #6b7280;
    }

    /* Sub-agent detail view */
    .subagent-detail {
      border-top: 1px solid #e5e7eb;
      padding: 1rem;
      background: white;
    }

    /* Sub-agent tabs */
    .subagent-tabs {
      display: flex;
      gap: 0.5rem;
      margin-bottom: 1rem;
      border-bottom: 2px solid #e5e7eb;
    }

    .subagent-tab {
      padding: 0.5rem 1rem;
      background: none;
      border: none;
      border-bottom: 2px solid transparent;
      margin-bottom: -2px;
      cursor: pointer;
      font-weight: 500;
      color: #6b7280;
      font-size: 0.875rem;
      transition: all 0.2s;
    }

    .subagent-tab:hover {
      color: #1f2937;
    }

    .subagent-tab.active {
      color: #6366f1;
      border-bottom-color: #6366f1;
    }

    /* Sub-agent config view */
    .subagent-config-view {
      display: flex;
      flex-direction: column;
      gap: 1rem;
    }

    .subagent-config-item label {
      display: block;
      font-size: 0.875rem;
      font-weight: 500;
      color: #6b7280;
      margin-bottom: 0.25rem;
    }

    .subagent-config-item > code {
      display: block;
      font-size: 0.875rem;
      background: #f3f4f6;
      padding: 0.5rem 0.75rem;
      border-radius: 0.25rem;
      word-break: break-all;
      font-family: 'Courier New', monospace;
    }

    .subagent-config-item > span {
      font-size: 0.875rem;
    }

    /* Direct pre children get light background, but not highlighted-code descendants */
    .subagent-config-item > pre {
      margin: 0;
      font-size: 0.875rem;
      background: #f3f4f6;
      padding: 0.75rem;
      border-radius: 0.25rem;
      overflow-x: auto;
      max-height: 12rem;
      overflow-y: auto;
      white-space: pre-wrap;
    }

    /* Highlighted code blocks within config items preserve their dark theme */
    .subagent-config-item .highlighted-code {
      max-height: 12rem;
      overflow-y: auto;
    }

    .subagent-error-label {
      color: #dc2626 !important;
    }

    .subagent-error-content {
      background: #fef2f2 !important;
      color: #991b1b;
    }

    /* Streaming indicator */
    .subagent-streaming {
      display: flex;
      align-items: center;
      gap: 0.5rem;
      color: #3b82f6;
      font-size: 0.875rem;
      margin-bottom: 0.75rem;
    }

    .subagent-streaming-dots {
      display: inline-flex;
      gap: 2px;
    }

    .subagent-streaming-dots span {
      width: 4px;
      height: 4px;
      background: #3b82f6;
      border-radius: 50%;
      animation: streaming-dot 1.4s infinite ease-in-out;
    }

    .subagent-streaming-dots span:nth-child(1) {
      animation-delay: 0s;
    }

    .subagent-streaming-dots span:nth-child(2) {
      animation-delay: 0.2s;
    }

    .subagent-streaming-dots span:nth-child(3) {
      animation-delay: 0.4s;
    }

    @keyframes streaming-dot {
      0%, 80%, 100% {
        opacity: 0.3;
        transform: scale(0.8);
      }
      40% {
        opacity: 1;
        transform: scale(1);
      }
    }

    .subagent-streaming-content {
      font-size: 0.875rem;
      background: #eff6ff;
      padding: 0.75rem;
      border-radius: 0.25rem;
      white-space: pre-wrap;
      margin-bottom: 0.75rem;
    }

    /* Sub-agent messages view */
    .subagent-messages-view {
      display: flex;
      flex-direction: column;
      gap: 0.75rem;
    }

    .subagent-messages-empty,
    .subagent-tools-empty,
    .subagent-middleware-empty {
      text-align: center;
      color: #6b7280;
      padding: 1rem;
    }

    /* Auto-Follow Filter Config Styles */
    .filter-config {
      background: #f9fafb;
      border: 1px solid #e5e7eb;
      border-radius: 0.5rem;
      padding: 1.5rem;
      margin-bottom: 1.5rem;
    }

    .filter-config-header {
      display: flex;
      justify-content: space-between;
      align-items: center;
      margin-bottom: 0.75rem;
    }

    .filter-config-header h3 {
      margin: 0;
      font-size: 1rem;
      font-weight: 600;
      color: #374151;
    }

    .filter-hint {
      font-size: 0.875rem;
      color: #6b7280;
      margin: 0 0 1rem 0;
    }

    .filter-fields {
      display: grid;
      grid-template-columns: repeat(auto-fit, minmax(200px, 1fr));
      gap: 1rem;
      margin-bottom: 1rem;
    }

    .filter-field {
      display: flex;
      flex-direction: column;
      gap: 0.25rem;
    }

    .filter-field label {
      font-size: 0.875rem;
      font-weight: 500;
      color: #374151;
    }

    .filter-field input {
      padding: 0.5rem 0.75rem;
      border: 1px solid #d1d5db;
      border-radius: 0.375rem;
      font-size: 0.875rem;
      background: white;
    }

    .filter-field input:focus {
      outline: none;
      border-color: #6366f1;
      box-shadow: 0 0 0 2px rgba(99, 102, 241, 0.2);
    }

    .field-hint {
      font-size: 0.75rem;
      color: #9ca3af;
      margin-top: 0.25rem;
    }

    .custom-scope-inputs {
      display: flex;
      gap: 0.5rem;
    }

    .custom-scope-inputs .scope-key {
      flex: 1;
    }

    .custom-scope-inputs .scope-value {
      flex: 1;
    }

    .filter-actions {
      display: flex;
      gap: 0.75rem;
      margin-top: 1rem;
    }

    .filter-actions .btn-primary {
      background: #6366f1;
      color: white;
      padding: 0.5rem 1rem;
      border: none;
      border-radius: 0.375rem;
      font-weight: 500;
      cursor: pointer;
      transition: background 0.2s;
    }

    .filter-actions .btn-primary:hover {
      background: #4f46e5;
    }

    .filter-actions .btn-secondary {
      background: white;
      color: #374151;
      padding: 0.5rem 1rem;
      border: 1px solid #d1d5db;
      border-radius: 0.375rem;
      font-weight: 500;
      cursor: pointer;
      transition: all 0.2s;
    }

    .filter-actions .btn-secondary:hover {
      background: #f3f4f6;
      border-color: #9ca3af;
    }

    .presence-status {
      display: flex;
      align-items: center;
      gap: 0.5rem;
      padding: 0.75rem;
      border-radius: 0.375rem;
      font-size: 0.875rem;
      margin-top: 1rem;
    }

    .presence-status.active {
      background: #d1fae5;
      color: #065f46;
    }

    .presence-status.inactive {
      background: #f3f4f6;
      color: #6b7280;
    }

    .status-icon {
      width: 8px;
      height: 8px;
      border-radius: 50%;
      flex-shrink: 0;
    }

    .status-icon.active {
      background: #10b981;
    }

    .status-icon.inactive {
      background: #9ca3af;
    }

    .status-icon.waiting {
      background: #f59e0b;
      animation: pulse 2s infinite;
    }

    @keyframes pulse {
      0%, 100% { opacity: 1; }
      50% { opacity: 0.5; }
    }

    /* Filter Badge Styles */
    .filter-badge-container {
      display: inline-block;
    }

    .filter-badge {
      display: inline-block;
      padding: 0.25rem 0.5rem;
      border-radius: 0.25rem;
      font-size: 0.75rem;
      font-weight: 500;
    }

    .filter-badge.all {
      background: #dbeafe;
      color: #1e40af;
    }

    .filter-badge.none {
      background: #f3f4f6;
      color: #6b7280;
    }

    .filter-badge.active {
      background: #d1fae5;
      color: #065f46;
    }

    /* Syntax highlighted code blocks */
    .highlighted-code {
      margin: 0;
      border-radius: 0.25rem;
      overflow-x: auto;
    }

    .highlighted-code pre {
      margin: 0;
      font-size: 0.875rem;
      line-height: 1.5;
      padding: 0.75rem;
      border-radius: 0.25rem;
      white-space: pre-wrap;
      word-wrap: break-word;
      overflow-wrap: break-word;
    }

    .highlighted-code code {
      font-family: 'Courier New', Consolas, Monaco, monospace;
    }
    """
  end
end
