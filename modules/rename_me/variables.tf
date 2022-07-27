variable "context" {
  description = "Project context."

  type = object({
    namespace = string
    stage     = string
    name      = string
  })
}

variable "todo" {
  description = "todo"

  type = string
}

# optional

