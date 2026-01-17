# Bedrock Knowledge Base
resource "aws_bedrockagent_knowledge_base" "kb" {
  name        = "${var.name_prefix}${var.kb_name}"
  description = "Knowledge base for agentic platform using S3 Vectors and Nova 2 multimodal embeddings"
  role_arn    = aws_iam_role.kb_role.arn

  knowledge_base_configuration {
    vector_knowledge_base_configuration {
      embedding_model_arn = "arn:aws:bedrock:${var.aws_region}::foundation-model/${var.embedding_model}"

      embedding_model_configuration {
        bedrock_embedding_model_configuration {
          dimensions          = var.vector_dimension
          embedding_data_type = var.embedding_data_type
        }
      }

      # Supplemental data storage for multimodal chunks
      supplemental_data_storage_configuration {
        storage_location {
          type = "S3"
          s3_location {
            uri = "s3://${aws_s3_bucket.kb_data.id}/"
          }
        }
      }
    }
    type = "VECTOR"
  }

  storage_configuration {
    type = "S3_VECTORS"
    s3_vectors_configuration {
      index_arn = aws_s3vectors_index.kb_index.index_arn
    }
  }

  tags = merge(var.common_tags, {
    Name           = "Agentic Platform Knowledge Base"
    EmbeddingModel = var.embedding_model
  })
}
