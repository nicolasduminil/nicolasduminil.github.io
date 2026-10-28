---
title: "My published books"
permalink: /books/
layout: single
author_profile: true
classes: wide
---

From J2EE to AI frameworks, more than twenty years of writing about Java enterprise development and the cloud.

{% assign latest = site.data.books | first %}
{% include book-card.html book=latest featured=true %}

<div class="book-grid">
{% for book in site.data.books offset:1 %}
  {% include book-card.html book=book %}
{% endfor %}
</div>
