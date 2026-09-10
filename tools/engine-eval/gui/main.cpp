// SPDX-License-Identifier: GPL-3.0-or-later
// SPDX-FileCopyrightText: 2026 Hexproof contributors

#include <QApplication>
#include <QComboBox>
#include <QDir>
#include <QFile>
#include <QHBoxLayout>
#include <QJsonArray>
#include <QJsonDocument>
#include <QJsonObject>
#include <QLabel>
#include <QPlainTextEdit>
#include <QPointer>
#include <QProcess>
#include <QPushButton>
#include <QScrollArea>
#include <QSet>
#include <QTest>
#include <QTimer>
#include <QVBoxLayout>
#include <QWidget>
#include <algorithm>

// A trusted hot-seat laboratory, not the production Hexproof client. All
// decision owners share this test process; privacy is qualified separately.
class Laboratory final : public QWidget
{
    Q_OBJECT
  public:
    Laboratory(const QStringList &command, const QString &output, bool automatic,
               const QJsonObject &workload)
        : m_output(output),
          m_automatic(automatic),
          m_workload(workload)
    {
        setWindowTitle("Hexproof — isolated rules-engine laboratory");
        resize(1160, 780);
        auto *layout = new QVBoxLayout(this);
        auto *disclaimer = new QLabel(
            "LOCAL HOT-SEAT EVALUATION · synthetic reference decks · not production integration",
            this);
        disclaimer->setTextFormat(Qt::PlainText);
        layout->addWidget(disclaimer);
        m_header = new QLabel("Starting engine…", this);
        m_header->setTextFormat(Qt::PlainText);
        layout->addWidget(m_header);
        m_viewer = new QComboBox(this);
        m_viewer->addItems({"Decision owner's view", "Spectator", "Seat 0", "Seat 1"});
        for (int seat = 2; seat < workload["players"].toArray().size(); ++seat)
            m_viewer->addItem(QString("Seat %1").arg(seat));
        layout->addWidget(m_viewer);
        connect(m_viewer, &QComboBox::currentIndexChanged, this, &Laboratory::renderView);
        m_state = new QPlainTextEdit(this);
        m_state->setReadOnly(true);
        layout->addWidget(m_state, 1);
        auto *scroll = new QScrollArea(this);
        scroll->setWidgetResizable(true);
        m_actions = new QWidget(scroll);
        m_actionLayout = new QVBoxLayout(m_actions);
        scroll->setWidget(m_actions);
        scroll->setMinimumHeight(250);
        layout->addWidget(scroll, 1);
        QDir().mkpath(output);
        m_trace.setFileName(output + "/gui-events.jsonl");
        if (!m_trace.open(QIODevice::WriteOnly | QIODevice::NewOnly)) {
            qFatal("Cannot create isolated evidence log");
        }
        record({{"type", "invocation"},
                {"arguments", QJsonArray::fromStringList(QCoreApplication::arguments())},
                {"platform", QGuiApplication::platformName()}});
        m_backend.setProcessChannelMode(QProcess::SeparateChannels);
        m_backend.setStandardErrorFile(output + "/backend.log");
        connect(&m_backend, &QProcess::readyReadStandardOutput, this, &Laboratory::receive);
        connect(&m_backend, &QProcess::errorOccurred, this, [this](QProcess::ProcessError) {
            m_header->setText(m_backend.errorString());
            QTimer::singleShot(0, qApp, [] { QCoreApplication::exit(2); });
        });
        connect(
            &m_backend, &QProcess::finished, this, [this](int code, QProcess::ExitStatus status) {
                if (!m_sawTerminal || code != 0 || status != QProcess::NormalExit) {
                    m_header->setText(
                        QString("Backend ended without a terminal result (exit %1)").arg(code));
                    grab().save(m_output + "/incomplete.png");
                    if (m_automatic)
                        QCoreApplication::exit(2);
                } else {
                    m_complete = true;
                    m_header->setText("Natural result and successful backend exit verified · " + m_finalSummary);
                    QTimer::singleShot(100, this, [this] {
                        grab().save(m_output + "/result.png");
                        if (m_automatic)
                            QCoreApplication::exit(0);
                    });
                }
            });
        m_backend.start(command.first(), command.mid(1));
        QTimer::singleShot(600000, this, [this] {
            if (!m_complete && m_automatic) {
                grab().save(m_output + "/timeout.png");
                m_backend.terminate();
                QCoreApplication::exit(124);
            }
        });
    }

    ~Laboratory() override
    {
        if (m_backend.state() != QProcess::NotRunning) {
            m_backend.closeWriteChannel();
            m_backend.terminate();
            if (!m_backend.waitForFinished(1000)) {
                m_backend.kill();
                m_backend.waitForFinished(1000);
            }
        }
    }

  private:
    void record(const QJsonObject &event)
    {
        m_trace.write(QJsonDocument(event).toJson(QJsonDocument::Compact) + '\n');
        m_trace.flush();
    }

    void receive()
    {
        m_buffer += m_backend.readAllStandardOutput();
        while (m_buffer.contains('\n')) {
            auto position = m_buffer.indexOf('\n');
            auto line = m_buffer.left(position);
            m_buffer.remove(0, position + 1);
            QJsonParseError error;
            auto document = QJsonDocument::fromJson(line, &error);
            if (error.error != QJsonParseError::NoError || !document.isObject()) {
                record({{"type", "invalid_backend_output"}, {"line", QString::fromUtf8(line)}});
                continue;
            }
            auto event = document.object();
            record(event);
            if (event["type"] == "result") {
                const auto players = event["view"].toObject()["players"].toArray();
                bool lethal = false;
                bool survivor = false;
                bool consistentWinner = !event.contains("winner");
                bool allOpponentsLost = true;
                QSet<QString> playerIds;
                QString winnerId;
                for (const auto &player : players) {
                    const QJsonObject playerObject = player.toObject();
                    const QJsonValue life = playerObject["life"];
                    lethal |= life.isDouble() && life.toInt() <= 0;
                    survivor |= life.isDouble() && life.toInt() > 0;
                    auto normalizeId = [](const QJsonValue &value) {
                        QString id =
                            value.isDouble() ? QString::number(value.toInt()) : value.toString();
                        return id.startsWith("player-") ? id.mid(7) : id;
                    };
                    playerIds.insert(normalizeId(playerObject["id"]));
                    winnerId = normalizeId(event["winner"]);
                    consistentWinner |=
                        event.contains("winner") && life.isDouble() && life.toInt() > 0 &&
                        normalizeId(player.toObject()["id"]) == normalizeId(event["winner"]);
                    if (event.contains("winner") && normalizeId(player.toObject()["id"]) != normalizeId(event["winner"]))
                        allOpponentsLost &= life.toInt() <= 0 || player.toObject()["hasLost"].toBool() ||
                                            player.toObject()["status"].toString() == "lost";
                    if (playerObject["hasWon"].toBool() && normalizeId(playerObject["id"]) != winnerId)
                        allOpponentsLost = false;
                }
                QSet<QString> requiredCategories = {"keep", "land", "cast", "mana", "pass"};
                if (m_workload["policy"] != "burn_v1")
                    requiredCategories.insert("attack_all");
                if (m_workload.isEmpty())
                    requiredCategories.insert("block_none");
                const int expectedPlayers = m_workload.isEmpty() ? 2 : m_workload["players"].toArray().size();
                if (!m_clickedCategories.contains(requiredCategories) ||
                    !event["gameOver"].toBool() || players.size() != expectedPlayers ||
                    playerIds.size() != expectedPlayers || (event.contains("winner") && !playerIds.contains(winnerId)) ||
                    (!lethal && expectedPlayers == 2) || !survivor || !allOpponentsLost || !consistentWinner ||
                    (event.contains("naturalCompletion") && !event["naturalCompletion"].toBool())) {
                    record({{"type", "invalid_terminal_result"}});
                    m_backend.terminate();
                    if (m_automatic)
                        QCoreApplication::exit(2);
                    continue;
                }
                m_sawTerminal = true;
                m_actions->setEnabled(false);
                m_finalSummary = QString("%1 · winner seat %2 · %3 native clicks")
                                     .arg(event["engine"].toString(), winnerId)
                                     .arg(m_decisions);
                m_header->setText(
                    "Natural result received — waiting for successful backend completion");
                QStringList finalLines{m_finalSummary, ""};
                for (const auto &value : players) {
                    const auto player = value.toObject();
                    finalLines << QString("%1 · life %2 · %3")
                                      .arg(player["name"].toString())
                                      .arg(player["life"].toInt())
                                      .arg(player["hasLost"].toBool() || player["status"] == "lost" ? "lost" : "winner");
                    finalLines << "Commander damage: " + QString::fromUtf8(QJsonDocument(player["commanderDamage"].toObject()).toJson(QJsonDocument::Compact));
                }
                finalLines << "" << "Full decisions and projections retained in gui-events.jsonl.";
                m_state->setPlainText(finalLines.join('\n'));
                m_backend.closeWriteChannel();
            } else if (event["type"] == "decision") {
                m_decision = event;
                showDecision();
            }
        }
    }

    void renderView()
    {
        int viewer = m_viewer->currentIndex() == 0   ? m_decision["actor"].toInt()
                     : m_viewer->currentIndex() == 1 ? -1
                                                     : m_viewer->currentIndex() - 2;
        for (const auto &value : m_decision["views"].toArray()) {
            auto view = value.toObject();
            if (view["viewer"].toInt(-2) != viewer)
                continue;
            QStringList lines;
            for (const auto &item : view["players"].toArray()) {
                auto player = item.toObject();
                lines << QString("%1 — life %2")
                             .arg(player["name"].toString())
                             .arg(player["life"].toInt());
            }
            for (const auto &item : view["zones"].toArray()) {
                auto zone = item.toObject();
                QStringList cards;
                for (const auto &cardItem : zone["cards"].toArray()) {
                    auto card = cardItem.toObject();
                    cards << card["name"].toString("Hidden card") +
                                 (card["tapped"].toBool() ? " [tapped]" : "");
                }
                if (!cards.isEmpty() || zone["zone"].toString() == "hand" ||
                    zone["zone"].toString() == "library")
                    lines << QString("Seat %1 · %2 (%3): %4")
                                 .arg(zone["owner"].toInt())
                                 .arg(zone["zone"].toString())
                                 .arg(zone["count"].toInt(zone["cards"].toArray().size()))
                                 .arg(cards.join(", "));
            }
            for (const auto &item : view["stack"].toArray())
                lines << "STACK: " + item.toObject()["name"].toString();
            m_state->setPlainText(lines.join('\n'));
            break;
        }
    }

    void showDecision()
    {
        if (++m_decisions > 15000) {
            QCoreApplication::exit(124);
            return;
        }
        m_header->setText(QString("%1 · decision %2 · seat %3 · %4")
                              .arg(m_decision["engine"].toString())
                              .arg(m_decisions)
                              .arg(m_decision["actor"].toInt())
                              .arg(m_decision["kind"].toString()));
        renderView();
        while (auto *item = m_actionLayout->takeAt(0)) {
            delete item->widget();
            delete item;
        }
        QStringList preference = {"keep", "land", "cast", "target_opponent", "target", "confirm",
                                  "attack_all", "block_none", "pass", "mana", "other"};
        if (m_decision["kind"] == "PLAY_MANA" || m_decision["kind"] == "PLAY_X_MANA")
            preference.prepend("mana");
        QPushButton *preferred = nullptr;
        int best = 100;
        const auto currentId = m_decision["id"];
        for (const auto &value : m_decision["actions"].toArray()) {
            auto action = value.toObject();
            auto *button = new QPushButton(action["label"].toString(), m_actions);
            button->setMinimumHeight(36);
            m_actionLayout->addWidget(button);
            connect(button, &QPushButton::clicked, this, [this, action, currentId] {
                if (m_decision["id"] != currentId || m_sentId == currentId)
                    return;
                m_sentId = currentId;
                m_clickedCategories.insert(action["category"].toString());
                QJsonObject response{{"type", "respond"},
                                     {"id", currentId},
                                     {"actor", m_decision["actor"]},
                                     {"response", action["response"]}};
                record({{"type", "native_button_click"},
                        {"id", currentId},
                        {"actor", m_decision["actor"]},
                        {"category", action["category"]},
                        {"label", action["label"]}});
                m_backend.write(QJsonDocument(response).toJson(QJsonDocument::Compact) + '\n');
            });
            int rank = preference.indexOf(action["category"].toString());
            if (m_decision["kind"] == "PICK_TARGET") {
                rank = 90;
                for (const auto &value : m_decision["views"].toArray().first().toObject()["players"].toArray()) {
                    const auto player = value.toObject();
                    if (player["id"] != m_decision["actor"] && !player["hasLost"].toBool() &&
                        action["cardName"] == player["name"])
                        rank = std::max(0, player["life"].toInt());
                }
            }
            if (rank >= 0 && rank < best) {
                best = rank;
                preferred = button;
            }
        }
        m_actionLayout->addStretch();
        if (m_decisions == 3 ||
            m_decision["kind"].toString().contains("Attack", Qt::CaseInsensitive))
            QTimer::singleShot(10, this, [this] { grab().save(m_output + "/decision.png"); });
        if (m_automatic && preferred) {
            QPointer<QPushButton> button = preferred;
            QTimer::singleShot(35, this, [this, button, currentId] {
                if (!button || m_decision["id"] != currentId)
                    return;
                auto *scroll =
                    qobject_cast<QScrollArea *>(m_actions->parentWidget()->parentWidget());
                if (scroll)
                    scroll->ensureWidgetVisible(button);
                // Real widget input, not calling the controller directly.
                QTest::mouseClick(button, Qt::LeftButton);
            });
        }
    }

    QString m_output;
    QString m_finalSummary;
    bool m_automatic = false;
    bool m_complete = false;
    bool m_sawTerminal = false;
    int m_decisions = 0;
    QProcess m_backend;
    QFile m_trace;
    QByteArray m_buffer;
    QJsonObject m_decision;
    QJsonObject m_workload;
    QJsonValue m_sentId;
    QSet<QString> m_clickedCategories;
    QLabel *m_header;
    QComboBox *m_viewer;
    QPlainTextEdit *m_state;
    QWidget *m_actions;
    QVBoxLayout *m_actionLayout;
};

int main(int argc, char **argv)
{
    QApplication app(argc, argv);
    auto args = app.arguments();
    const bool automatic = args.removeAll("--auto") > 0;
    QJsonObject workload;
    const int workloadArgument = args.indexOf("--workload");
    if (workloadArgument > 0 && workloadArgument + 2 < args.size()) {
        QFile file(args[workloadArgument + 1]);
        if (!file.open(QIODevice::ReadOnly))
            return 2;
        for (const auto &value : QJsonDocument::fromJson(file.readAll()).object()["workloads"].toArray())
            if (value.toObject()["id"].toString() == args[workloadArgument + 2])
                workload = value.toObject();
        if (workload.isEmpty())
            return 2;
        args.remove(workloadArgument, 3);
    }
    const int separator = args.indexOf("--");
    if (separator != 2 || args.size() <= separator + 1) {
        qCritical("Usage: engine-lab [--auto] [--workload file id] /new/output/directory -- backend [args...]");
        return 2;
    }
    if (QFile::exists(args[1] + "/gui-events.jsonl")) {
        qCritical("Refusing to overwrite existing GUI evidence");
        return 2;
    }
    Laboratory window(args.mid(separator + 1), args[1], automatic, workload);
    window.show();
    return app.exec();
}

#include "main.moc"
