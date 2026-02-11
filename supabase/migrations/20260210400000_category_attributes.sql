-- ============================================================================
-- CATEGORY ATTRIBUTES SYSTEM
-- Adds structured attributes to skills for better helper matching
-- ============================================================================

-- Add model_type to skills: 'bulletin' (apply/negotiate) or 'service_menu' (fixed rate, direct book)
ALTER TABLE skills ADD COLUMN IF NOT EXISTS model_type TEXT DEFAULT 'bulletin' CHECK (model_type IN ('bulletin', 'service_menu'));

-- Add attributes_schema to skills: JSON schema defining what attributes this skill has
-- Example: {"cleaning_types": {"type": "multi", "options": ["regular", "deep", "post_obra"]}}
ALTER TABLE skills ADD COLUMN IF NOT EXISTS attributes_schema JSONB DEFAULT '{}';

-- Add skill_attributes to user_skills: the helper's actual attribute values
-- Example: {"cleaning_types": ["regular", "deep"], "includes_windows": true}
ALTER TABLE user_skills ADD COLUMN IF NOT EXISTS skill_attributes JSONB DEFAULT '{}';

-- ============================================================================
-- UPDATE EXISTING SKILLS WITH NEW CATEGORIES
-- ============================================================================

-- Update cleaning to service_menu model
UPDATE skills SET
  model_type = 'service_menu',
  attributes_schema = '{
    "cleaning_types": {
      "type": "multi",
      "label": "Tipo de limpieza",
      "options": [
        {"value": "regular", "label": "Regular"},
        {"value": "deep", "label": "Profunda"},
        {"value": "post_obra", "label": "Fin de obra"}
      ]
    },
    "includes_free": {
      "type": "multi",
      "label": "Incluyo sin coste extra",
      "options": [
        {"value": "windows", "label": "Ventanas"},
        {"value": "oven", "label": "Horno"},
        {"value": "fridge", "label": "Nevera"},
        {"value": "ironing", "label": "Plancha"}
      ]
    }
  }'::jsonb
WHERE name = 'cleaning';

-- Update painting with attributes
UPDATE skills SET
  attributes_schema = '{
    "location": {
      "type": "multi",
      "label": "Donde pinto",
      "options": [
        {"value": "interior", "label": "Interior"},
        {"value": "exterior", "label": "Exterior"}
      ]
    },
    "heights": {
      "type": "single",
      "label": "Alturas",
      "options": [
        {"value": "ground_only", "label": "Solo planta baja"},
        {"value": "up_to_2", "label": "Hasta 2 plantas"},
        {"value": "any", "label": "Sin limite"}
      ]
    },
    "brings_materials": {
      "type": "single",
      "label": "Traigo materiales",
      "options": [
        {"value": "yes", "label": "Si (incluido en precio)"},
        {"value": "no", "label": "No (cliente aporta)"}
      ]
    }
  }'::jsonb
WHERE name = 'painting';

-- Update gardening with attributes
UPDATE skills SET
  attributes_schema = '{
    "services": {
      "type": "multi",
      "label": "Servicios",
      "options": [
        {"value": "maintenance", "label": "Mantenimiento"},
        {"value": "pruning", "label": "Poda"},
        {"value": "lawn", "label": "Cesped"},
        {"value": "irrigation", "label": "Riego"},
        {"value": "design", "label": "Diseno"}
      ]
    },
    "has_tools": {
      "type": "single",
      "label": "Tengo herramientas propias",
      "options": [
        {"value": "yes", "label": "Si"},
        {"value": "no", "label": "No"}
      ]
    }
  }'::jsonb
WHERE name = 'gardening';

-- Update moving with attributes
UPDATE skills SET
  attributes_schema = '{
    "has_vehicle": {
      "type": "single",
      "label": "Tengo vehiculo",
      "options": [
        {"value": "no", "label": "No"},
        {"value": "car", "label": "Coche"},
        {"value": "van", "label": "Furgoneta"}
      ]
    },
    "heavy_lifting": {
      "type": "single",
      "label": "Puedo cargar muebles pesados",
      "options": [
        {"value": "yes", "label": "Si"},
        {"value": "no", "label": "No"}
      ]
    }
  }'::jsonb
WHERE name = 'moving';

-- Update furniture assembly with attributes
UPDATE skills SET
  attributes_schema = '{
    "experience_with": {
      "type": "multi",
      "label": "Experiencia con",
      "options": [
        {"value": "ikea", "label": "IKEA"},
        {"value": "other_furniture", "label": "Otros muebles"},
        {"value": "appliances", "label": "Electrodomesticos"}
      ]
    },
    "has_tools": {
      "type": "single",
      "label": "Tengo herramientas",
      "options": [
        {"value": "yes", "label": "Si"},
        {"value": "no", "label": "No"}
      ]
    }
  }'::jsonb
WHERE name = 'furniture_assembly';

-- ============================================================================
-- ADD NEW SKILLS: MANITAS, RECADOS
-- ============================================================================

-- Add manitas (handyman) skill
INSERT INTO skills (name, name_es, icon, category, model_type, attributes_schema) VALUES
  ('handyman', 'Manitas', '🔧', 'mantenimiento', 'bulletin', '{
    "can_help_with": {
      "type": "multi",
      "label": "Puedo ayudar con",
      "options": [
        {"value": "basic_plumbing", "label": "Fontaneria basica"},
        {"value": "basic_electrical", "label": "Electricidad basica"},
        {"value": "carpentry", "label": "Carpinteria"},
        {"value": "locksmith", "label": "Cerrajeria"},
        {"value": "hanging", "label": "Colgar cosas"},
        {"value": "small_repairs", "label": "Pequenas reparaciones"}
      ]
    },
    "description": {
      "type": "text",
      "label": "Descripcion libre",
      "placeholder": "Describe que tipo de trabajos puedes hacer..."
    }
  }')
ON CONFLICT (name) DO UPDATE SET
  name_es = EXCLUDED.name_es,
  icon = EXCLUDED.icon,
  category = EXCLUDED.category,
  model_type = EXCLUDED.model_type,
  attributes_schema = EXCLUDED.attributes_schema;

-- Add recados (errands) skill
INSERT INTO skills (name, name_es, icon, category, model_type, attributes_schema) VALUES
  ('errands', 'Recados', '🛵', 'servicios', 'bulletin', '{
    "has_vehicle": {
      "type": "single",
      "label": "Tengo vehiculo",
      "options": [
        {"value": "no", "label": "No"},
        {"value": "yes", "label": "Si"}
      ]
    },
    "available_for": {
      "type": "multi",
      "label": "Disponible para",
      "options": [
        {"value": "shopping", "label": "Compras"},
        {"value": "pickups", "label": "Recogidas"},
        {"value": "deliveries", "label": "Entregas"},
        {"value": "accompaniment", "label": "Acompanamiento"}
      ]
    }
  }')
ON CONFLICT (name) DO UPDATE SET
  name_es = EXCLUDED.name_es,
  icon = EXCLUDED.icon,
  category = EXCLUDED.category,
  model_type = EXCLUDED.model_type,
  attributes_schema = EXCLUDED.attributes_schema;

-- Update miscellaneous to be the catch-all "otros" category
UPDATE skills SET
  attributes_schema = '{
    "category_free": {
      "type": "text",
      "label": "Categoria",
      "placeholder": "Ej: Costura, Bricolaje..."
    },
    "description": {
      "type": "text",
      "label": "Descripcion",
      "placeholder": "Describe lo que puedes ofrecer..."
    }
  }'::jsonb
WHERE name = 'miscellaneous';

-- ============================================================================
-- INDEX FOR FASTER JSONB QUERIES
-- ============================================================================
CREATE INDEX IF NOT EXISTS idx_user_skills_attributes ON user_skills USING GIN (skill_attributes);
