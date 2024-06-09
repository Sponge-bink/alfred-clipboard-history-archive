import sqlite3
import sys
import datetime
import json


def search_clipboard(keyword, db_path):
    conn = sqlite3.connect(db_path)
    c = conn.cursor()

    # Search for the keyword in the 'item' column of the 'clipboard' table
    c.execute("SELECT item, ts FROM clipboard WHERE item LIKE ?", ('%' + keyword + '%',))
    results = c.fetchall()

    output = []
    for item, ts in results:
        title = item[:120] if len(item) > 120 else item
        output.append({
            'title': title,
            'arg': item,
            'timestamp': ts + 978307200,
            'subtitle': f"{str(item.count('\n') + 1) + " lines, " if item.count('\n') else ""}{len(item)} characters, copied at {datetime.datetime.fromtimestamp(ts + 978307200).strftime('%Y-%m-%d %-I:%M:%S %p')}"
        })

    conn.close()
    return output


if __name__ == "__main__":
    keyword = sys.argv[1]
    db_path = sys.argv[2]

    results = search_clipboard(keyword, db_path)

    response_dict = {'skipknowledge': True}

    result_bridge = sorted(results, key=lambda x: x['timestamp'], reverse=True)

    for dict_ in result_bridge:
        dict_.pop('timestamp')

    response_dict['items'] = result_bridge

    sys.stdout.write(json.dumps(response_dict))
