variable "ecs_exec_services" {
  description = "Services that get ECS Exec. Each gets the ssmmessages permissions on its task role, and application turns on enable_execute_command from the flag published here. Off by default: every enabled service can be entered with a shell."
  type        = list(string)
  default     = []
}
