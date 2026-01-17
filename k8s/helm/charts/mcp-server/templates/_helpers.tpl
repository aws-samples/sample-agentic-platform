{{- define "mcp.name" -}}
{{- .Release.Name }}
{{- end }}

{{- define "mcp.namespace" -}}
{{- .Release.Namespace }}
{{- end }}

{{- define "mcp.image" -}}
{{- $config := (lookup "v1" "ConfigMap" .Values.namespace "agentic-platform-config").data -}}
{{- if $config -}}
{{- printf "%s.dkr.ecr.%s.amazonaws.com/%s:%s" $config.AWS_ACCOUNT_ID $config.AWS_DEFAULT_REGION .Values.image.repository .Values.image.tag -}}
{{- else -}}
{{- printf "%s:%s" .Values.image.repository .Values.image.tag -}}
{{- end -}}
{{- end }}

{{- define "mcp.irsaRoleArn" -}}
{{- if .Values.serviceAccount.irsaConfigKey -}}
{{- $config := (lookup "v1" "ConfigMap" .Values.namespace "agentic-platform-config").data -}}
{{- if $config -}}
{{- index $config .Values.serviceAccount.irsaConfigKey -}}
{{- end -}}
{{- end -}}
{{- end }}

{{- define "mcp.parameterStoreRegion" -}}
{{- $config := (lookup "v1" "ConfigMap" .Values.namespace "agentic-platform-config").data -}}
{{- if $config -}}
{{- $config.AWS_DEFAULT_REGION -}}
{{- else -}}
us-east-1
{{- end -}}
{{- end }}
