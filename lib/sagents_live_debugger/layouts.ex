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
        <%= @inner_content %>
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
      margin-bottom: 0.5rem;
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
    """
  end
end
