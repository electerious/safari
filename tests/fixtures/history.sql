CREATE TABLE history_items (
  id INTEGER PRIMARY KEY,
  url TEXT NOT NULL UNIQUE
);

CREATE TABLE history_visits (
  id INTEGER PRIMARY KEY,
  history_item INTEGER NOT NULL,
  visit_time REAL NOT NULL,
  title TEXT
);

INSERT INTO history_items (id, url) VALUES
  (1, 'https://example.com/'),
  (2, 'https://example.org/article');

INSERT INTO history_visits (id, history_item, visit_time, title) VALUES
  (1, 1, 100.0, 'Older visit'),
  (2, 2, 300.0, NULL),
  (3, 1, 200.0, 'Middle visit');
