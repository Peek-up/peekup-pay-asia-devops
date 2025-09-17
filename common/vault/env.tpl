# This template is no longer needed for .env updates but can be kept for other purposes
{{ with secret "kv/env" }} 
# This file is automatically managed by the two-way sync system
# Manual edits may be overwritten
{{ range $k, $v := .Data.data }}
{{ $k }}={{ $v }}{{ end }}{{ end }}