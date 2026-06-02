{# Rounds a money column to 2 decimals and labels it for marts. #}
{% macro money(column_name) %}
    round({{ column_name }}, 2)
{% endmacro %}
