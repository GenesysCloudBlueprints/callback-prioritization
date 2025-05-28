// Create a Data Action integration
module "data_action" {
  source                          = "git::https://github.com/GenesysCloudDevOps/public-api-data-actions-integration-module?ref=main"
  integration_name                = "Callback Prioritization"
  integration_creds_client_id     = var.client_id
  integration_creds_client_secret = var.client_secret
}

// Create a Get Callback Priority Data Action
resource "genesyscloud_integration_action" "action-1" {
  name                   = "Get Callback Priority"
  category               = "${module.data_action.integration_name}"
  integration_id         = "${module.data_action.integration_id}"
  contract_input = jsonencode({
    "type" = "object",
    "properties" = {
      "conversationId" = {
        "type" = "string"
      }
    },
    "required" = [ "conversationId" ]
  })
  contract_output = jsonencode({
    "type" = "object",
    "properties" = {
      "priority" = {
        "type" = "integer"
      }
    }
  })
  config_request {
    # Use '$${' to indicate a literal '${' in template strings. Otherwise Terraform will attempt to interpolate the string
    # See https://www.terraform.io/docs/language/expressions/strings.html#escape-sequences
    request_url_template = "/api/v2/conversations/callbacks/$${input.conversationId}"
    request_type         = "GET"
    request_template     = "$${input.rawRequest}"
    headers = {}
  }
  config_response {
    translation_map = {
      "pIdArray" = "$.participants[?(@.purpose=='acd')].conversationRoutingData.priority"
    }
    translation_map_defaults = {
      "pIdArray" = "[\"\"]"
    }
    success_template = "{\"priority\": $${successTemplateUtils.firstFromArray(\"$${pIdArray}\", \"$esc.quote$esc.quote\")}}"
  }

  depends_on = [module.data_action]
}

// Create a Get Interaction State Data Action
resource "genesyscloud_integration_action" "action-2" {
  name                   = "Get Interaction State"
  category               = "${module.data_action.integration_name}"
  integration_id         = "${module.data_action.integration_id}"
  contract_input = jsonencode({
    "type" = "object",
    "properties" = {
      "conversationId" = {
        "type" = "string"
      }
    }
  })
  contract_output = jsonencode({
    "type" = "object",
    "properties" = {
      "state" = {
        "type" = "string"
      }
    }
  })
  config_request {
    # Use '$${' to indicate a literal '${' in template strings. Otherwise Terraform will attempt to interpolate the string
    # See https://www.terraform.io/docs/language/expressions/strings.html#escape-sequences
    request_url_template = "/api/v2/conversations/$${input.conversationId}"
    request_type         = "GET"
    request_template     = "$${input.rawRequest}"
    headers = {}
  }
  config_response {
    translation_map = {
      "state" = "$.participants[0].callbacks[0].state"
    }
    translation_map_defaults = {
      "state": "disconnected"
    }
    success_template = "{\"state\": $${state}}"
  }

  depends_on = [module.data_action]
}

// Create a Update Callback Priority Data Action
resource "genesyscloud_integration_action" "action-3" {
  name                   = "Update Callback Priority"
  category               = "${module.data_action.integration_name}"
  integration_id         = "${module.data_action.integration_id}"
  contract_input = jsonencode({
    "type" = "object",
    "properties" = {
      "conversationId" = {
        "type" = "string"
      },
      "priority" = {
        "type" = "integer"
      }
    },
    "required" = [ "conversationId", "priority" ]
  })
  contract_output = jsonencode({
    "type" = "object",
    "properties" = {
      "priority" = {
        "type" = "integer"
      }
    }
  })
  config_request {
    # Use '$${' to indicate a literal '${' in template strings. Otherwise Terraform will attempt to interpolate the string
    # See https://www.terraform.io/docs/language/expressions/strings.html#escape-sequences
    request_url_template = "/api/v2/routing/conversations/$${input.conversationId}"
    request_type         = "PATCH"
    request_template     = "{\n  \"priority\":$${input.priority}\n}"
    headers = {}
  }
  config_response {
    translation_map = {
      "priority": "$.priority"
    }
    translation_map_defaults = {
      "priority": "0"
    }
    success_template = "{\"priority\": $${priority}}"
  }

  depends_on = [module.data_action]
}

// Configures the architect workflow
resource "genesyscloud_flow" "workflow" {
  filepath = "${path.module}/Callback-Prioritization-Workflow.yaml"
  file_content_hash = filesha256("${path.module}/Callback-Prioritization-Workflow.yaml")
  substitutions = {
    flow_name               = "Callback Prioritization"
    division                = "Home"
    default_language        = "en-us"
    data_action_category    = "${module.data_action.integration_name}"
    get_callback_priority   = "${genesyscloud_integration_action.action-1.name}"
    get_interaction_state   = "${genesyscloud_integration_action.action-2.name}"
    update_callback_priority= "${genesyscloud_integration_action.action-3.name}"
  }

  depends_on = [ module.data_action,
    genesyscloud_integration_action.action-1,
    genesyscloud_integration_action.action-2,
    genesyscloud_integration_action.action-3
  ]
}

// Create a Trigger
resource "genesyscloud_processautomation_trigger" "trigger" {
  name       = "Callback Prioritization"
  topic_name = "v2.detail.events.conversation.{id}.acd.start"
  enabled    = true
  target {
    id   = genesyscloud_flow.workflow.id
    type = "Workflow"
    workflow_target_settings {
      data_format = "TopLevelPrimitives"
    }
  }
  match_criteria = jsonencode([
    {
      "jsonPath" : "mediaType",
      "operator" : "Equal",
      "value" : "CALLBACK"
    }
  ])

  depends_on = [ genesyscloud_flow.workflow ]
}