extends Node

# Helper to build multipart/form-data bodies.

func build_multipart(boundary: String, field: String, filename: String, content_type: String, data: PackedByteArray) -> PackedByteArray:
	var prefix := "--%s\r\nContent-Disposition: form-data; name=\"%s\"; filename=\"%s\"\r\nContent-Type: %s\r\n\r\n" % [boundary, field, filename, content_type]
	var suffix := "\r\n--%s--\r\n" % boundary

	var out := PackedByteArray()
	out.append_array(prefix.to_utf8_buffer())
	out.append_array(data)
	out.append_array(suffix.to_utf8_buffer())
	return out
