{{- define "app.labels" -}}
app.kubernetes.io/name: {{ .Values.component }}
app.kubernetes.io/instance: {{ .Release.Name }}
app.kubernetes.io/managed-by: {{ .Release.Service }}
{{- end }}

{{- define "app.selector" -}}
app.kubernetes.io/name: {{ .Values.component }}
app.kubernetes.io/instance: {{ .Release.Name }}
{{- end }}

{{- define "app.isApi" -}}
{{- if eq .Values.component "api" }}true{{ end }}
{{- end }}

{{- define "app.checks" -}}
{{- if not (has .Values.component (list "api" "worker")) }}
{{- fail (printf "component must be api or worker, got %q" .Values.component) }}
{{- end }}
{{- if and .Values.namespace (ne .Values.namespace .Release.Namespace) }}
{{- fail (printf "release namespace %q is not %q, where eks-cluster set up Pod Identity" .Release.Namespace .Values.namespace) }}
{{- end }}
{{- end }}
