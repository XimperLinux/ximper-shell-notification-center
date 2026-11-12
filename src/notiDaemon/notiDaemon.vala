namespace XimperShellNotificationCenter {
    /** Return true to remove notification, false to skip */
    public delegate bool notification_filter_func (Notification notification);

    [DBus (name = "org.freedesktop.Notifications")]
    public class NotiDaemon : Object {
        private uint32 noti_id = 0;
        private HashTable<string, uint32> synchronous_ids =
            new HashTable<string, uint32> (str_hash, str_equal);
        private Gee.HashSet<uint32> notification_ids = new Gee.HashSet<uint32> ();
        // Non-critical control-center notifications, oldest update first.
        private Queue<uint32> history_ids = new Queue<uint32> ();

        /** Do Not Disturb state */
        internal bool dnd { get; set; default = false; }
        /** Called when Do Not Disturb state changes */
        internal signal void on_dnd_toggle (bool dnd);

        public NotiDaemon () {
            this.notify["dnd"].connect (() => on_dnd_toggle (dnd));

            // Init dnd from gsettings
            self_settings.bind ("dnd-state", this, "dnd", SettingsBindFlags.DEFAULT);
        }

        internal uint n_notifications {
            get {
                if (notifications_widget == null) return 0;
                return notifications_widget.n_notifications;
            }
        }

        internal void request_dismiss_notification_id (uint32 id,
                                                       ClosedReasons reason,
                                                       bool ignore_cc) {
            // Expired, non-transient notifications should not be fully dismissed, only hidden
            if (reason == ClosedReasons.EXPIRED && !ignore_cc) {
                debug ("Hiding floating notification with ID:%u, reason:%s",
                       id, reason.to_string ());
                floating_notifications.remove_notification (id);
                return;
            }

            dismiss_notification_id (id, reason);
            ximper_shell_notification_center_daemon.emit_subscribe ();
        }

        private void dismiss_notification_id (uint32 id, ClosedReasons reason) {
            debug ("Dismissing notification with ID:%u, reason:%s",
                   id, reason.to_string ());
            NotificationClosed (id, reason);
            notification_ids.remove (id);
            history_ids.remove (id);

            if (notifications_widget != null) {
                notifications_widget.remove_notification (id);
            }
            if (floating_notifications != null) {
                floating_notifications.remove_notification (id);
            }
        }

        internal bool trim_history () {
            uint limit = ConfigModel.instance.notification_history_limit;
            if (limit == 0 || history_ids.length <= limit) return false;
            while (history_ids.length > limit) {
                dismiss_notification_id (history_ids.peek_head (), ClosedReasons.UNDEFINED);
            }
            return true;
        }

        internal inline void request_dismiss_notification (NotifyParams param,
                                                           ClosedReasons reason) {
            request_dismiss_notification_id (param.applied_id, reason, param.ignore_cc ());
        }

        internal void request_dismiss_notification_group (string group_name_id,
                                                          Gee.Set<uint32> ids,
                                                          ClosedReasons reason) {
            debug ("Dismissing notification group with ID:%s, reason:%s",
                   group_name_id, reason.to_string ());
            foreach (unowned uint32 id in ids) {
                NotificationClosed (id, reason);
                notification_ids.remove (id);
                history_ids.remove (id);
                if (floating_notifications != null) {
                    floating_notifications.remove_notification (id);
                }
            }
            if (notifications_widget != null) {
                notifications_widget.remove_group (group_name_id);
            }

            ximper_shell_notification_center_daemon.emit_subscribe ();
        }

        internal void invalidate_all_notifications (ClosedReasons reason) {
            foreach (uint32 id in notification_ids) {
                NotificationClosed (id, reason);
            }
            notification_ids.clear ();
            history_ids.clear ();
            synchronous_ids.remove_all ();
        }

        internal void request_dismiss_all_notifications (ClosedReasons reason) {
            debug ("Dismissing all notifications, reason:%s", reason.to_string ());
            invalidate_all_notifications (reason);
            remove_all_floating_notifications (false, null);
            if (notifications_widget != null) {
                notifications_widget.remove_all_notifications (true);
            }

            ximper_shell_notification_center_daemon.emit_subscribe ();
        }

        /** Hides all floating notifications (closes transient) */
        internal inline void remove_all_floating_notifications (bool transition,
                                                                notification_filter_func ?func) {
            if (floating_notifications == null) return;
            debug ("Hiding all floating notifications");
            floating_notifications.remove_all_notifications (transition, (notification) => {
                if (func == null || func (notification)) {
                    // Send DISMISSED to valid TRANSIENT notifications
                    unowned NotifyParams param = notification.param;
                    if (param.ignore_cc () && notification_ids.remove (param.applied_id)) {
                        debug ("Closing floating-only notification with ID:%u while hiding",
                               param.applied_id);
                        NotificationClosed (param.applied_id, ClosedReasons.DISMISSED);
                    }
                    return true;
                }
                return false;
            });
        }

        /** Hides/closes latest floating notification */
        internal void hide_latest_floating_notification (bool close) {
            if (floating_notifications == null) return;
            NotifyParams ?param = floating_notifications.get_latest_notification ();
            if (param == null) {
                return;
            }

            // note: Hiding a TRANSIENT notification acts as closing it
            if (close || param.ignore_cc ()) {
                request_dismiss_notification (param, ClosedReasons.DISMISSED);
            } else {
                floating_notifications.remove_notification (param.applied_id);
            }
        }

        /** Activates the `action_index` action of the latest notification */
        internal void invoke_latest_floating_action (uint32 action_index) {
            if (floating_notifications == null) return;
            floating_notifications.latest_notification_action (action_index);
        }

        /*
         * D-Bus Specification
         * https://specifications.freedesktop.org/notification-spec/latest/ar01s09.html
         */

        /**
         * It returns an array of strings. Each string describes an optional
         * capability implemented by the server.
         *
         * New vendor-specific caps may be specified as long as they start with
         * "x-vendor". For instance, "x-gnome-foo-cap". Capability names must
         * not contain spaces. They are limited to alphanumeric characters
         * and dashes ("-").
         */
        [DBus (name = "GetCapabilities")]
        public string[] get_capabilities () throws DBusError, IOError {
            return {
                       "actions",
                       "body",
                       "body-markup",
                       "body-images",
                       "persistence",
                       "synchronous",
                       "private-synchronous",
                       "x-canonical-private-synchronous",
                       "inline-reply",
            };
        }

        /**
         * Sends a notification to the notification server.
         *
         * If replaces_id is 0, the return value is a UINT32 that represent
         * the notification. It is unique, and will not be reused unless a
         * MAXINT number of notifications have been generated. An acceptable
         * implementation may just use an incrementing counter for the ID.
         * The returned ID is always greater than zero. Servers must make
         * sure not to return zero as an ID.
         *
         * If replaces_id is not 0, the returned value is the same value
         * as replaces_id.
         */
        [DBus (name = "Notify")]
        public uint32 new_notification (string app_name,
                                        uint32 replaces_id,
                                        string app_icon,
                                        string summary,
                                        string body,
                                        string[] actions,
                                        HashTable<string, Variant> hints,
                                        int expire_timeout) throws DBusError, IOError {
            uint32 id = replaces_id;
            if (!notification_ids.contains (replaces_id)) {
                id = ++noti_id;
            }
            id = uint32.max (id, 1);

            var param = new NotifyParams (
                id,
                app_name,
                replaces_id,
                app_icon,
                summary,
                body,
                actions,
                hints,
                expire_timeout);

            debug ("Notification (ID:%u, state: %s): %s\n",
                   param.applied_id, param.status_state.to_string (), param.to_string ());

            // Get the notification id to replace
            uint32 notification_id_to_replace = 0;
            if (id == replaces_id) {
                notification_id_to_replace = replaces_id;
            } else if (param.synchronous != null
                       && param.synchronous.length > 0) {
                // Tries replacing without replaces_id instead
                uint32 r_id;
                // if there is any notification to replace
                if (synchronous_ids.lookup_extended (
                        param.synchronous, null, out r_id)) {
                    notification_id_to_replace = r_id;
                }
                synchronous_ids.set (param.synchronous, id);
            }

            // Don't show the floating notification if disabled and not transient
            string[] hide_floating_notification_reasons = {};
            if (param.status_state != NotificationStatusEnum.ENABLED
                && param.status_state != NotificationStatusEnum.TRANSIENT) {
                hide_floating_notification_reasons +=
                    "Notification status is not Enabled or Transient in Config";
            }
            // Don't show the notification window if the control center is open
            if (control_center.get_visibility ()) {
                hide_floating_notification_reasons += "Control Center is visible";
            }
            // Don't show the notification window if dnd or inhibited
            if (!param.bypasses_dnd () && (dnd || ximper_shell_notification_center_daemon.inhibited)) {
                hide_floating_notification_reasons +=
                    "Do Not Disturb is enabled or an Inhibitor is running";
            }

            bool added = false;
            bool removed = false;

            if (floating_notifications != null
                    && hide_floating_notification_reasons.length == 0) {
                added = true;
                if (notification_id_to_replace > 0) {
                    debug ("Replacing Notification: ID:%u -> ID:%u\n",
                           notification_id_to_replace, param.applied_id);
                    floating_notifications.replace_notification (notification_id_to_replace, param);
                } else {
                    debug ("Adding Floating Notification: ID:%u\n", param.applied_id);
                    floating_notifications.add_notification (param);
                }
            } else {
                debug ("Not displaying floating Notification: ID:%u, Reasons: {\"%s\"}\n",
                       param.applied_id,
                       string.joinv ("\", \"", hide_floating_notification_reasons));
                if (notification_id_to_replace > 0) {
                    removed = true;

                    // Remove the old notification due to the replacement possibly
                    // being Control Center-only
                    debug ("Removing replaced Floating Notification: ID:%u\n",
                           notification_id_to_replace);
                    if (floating_notifications != null) {
                        floating_notifications.remove_notification (notification_id_to_replace);
                    }
                }
            }

            bool in_history = notifications_widget != null && !param.ignore_cc ();
            if (in_history) {
                added = true;
                if (notification_id_to_replace > 0) {
                    debug ("Replacing CC Notification: ID:%u -> ID:%u\n",
                           notification_id_to_replace, param.applied_id);
                    notifications_widget.replace_notification (notification_id_to_replace, param);
                } else {
                    debug ("Adding Control Center Notification: ID:%u\n", param.applied_id);
                    notifications_widget.add_notification (param);
                }
            } else {
                debug ("Not Placing Notification in CC: ID:%u\n", param.applied_id);
                if (notification_id_to_replace > 0) {
                    removed = true;

                    // Remove the old notification due to it possibly being floating-only
                    debug ("Removing replaced CC Notification: ID:%u\n",
                           notification_id_to_replace);
                    if (notifications_widget != null) {
                        notifications_widget.remove_notification (notification_id_to_replace);
                    }
                }
            }

            // Store notification IDs
            if (added || removed) {
                if (notification_id_to_replace > 0) {
                    notification_ids.remove (notification_id_to_replace);
                    history_ids.remove (notification_id_to_replace);
                }
                if (added) {
                    notification_ids.add (id);
                }
                if (in_history && param.urgency != UrgencyLevels.CRITICAL) {
                    history_ids.push_tail (id);
                    trim_history ();
                }

                ximper_shell_notification_center_daemon.emit_subscribe ();
            }

            debug ("\n");
            return id;
        }

        /**
         * Causes a notification to be forcefully closed and removed from the
         * user's view. It can be used, for example, in the event that what
         * the notification pertains to is no longer relevant, or to cancel a
         * notification with no expiration time.
         *
         * The NotificationClosed signal is emitted by this method.
         *
         * If the notification no longer exists, an empty D-BUS Error message
         * is sent back.
         */
        [DBus (name = "CloseNotification")]
        public void close_notification (uint32 id) throws DBusError, IOError {
            if (!notification_ids.contains (id)) {
                throw new DBusError.INVALID_ARGS ("Unknown notification ID: %u", id);
            }
            request_dismiss_notification_id (id, ClosedReasons.CLOSED_BY_CLOSENOTIFICATION, false);
        }

        /**
         * This message returns the information on the server. Specifically, the
         * server name, vendor, and version number.
         */
        [DBus (name = "GetServerInformation")]
        public void get_server_information (out string name,
                                            out string vendor,
                                            out string version,
                                            out string spec_version)
        throws DBusError, IOError {
            name = "XimperShellNotificationCenter";
            vendor = "XimperLinux";
            version = Constants.VERSIONNUM;
            spec_version = "1.3";
        }

        /**
         * A completed notification is one that has timed out, or has been
         * dismissed by the user.
         *
         * The ID specified in the signal is invalidated before the signal
         * is sent and may not be used in any further communications
         * with the server.
         */
        public signal void NotificationClosed (uint32 id, uint32 reason);

        /**
         * This signal is emitted when one of the following occurs:
         *
         * - The user performs some global "invoking" action upon a
         * notification. For instance, clicking somewhere on the
         * notification itself.
         *
         * - The user invokes a specific action as specified in the original
         * Notify request. For example, clicking on an action button.
         *
         * #Note
         *
         * Clients should not assume the server will generate this signal.
         * Some servers may not support user interaction at all, or may not
         * support the concept of being able to "invoke" a notification.
         */
        public signal void ActionInvoked (uint32 id, string action_key);

        /**
         * This signal can be emitted before a ActionInvoked signal. It
         * carries an activation token that can be used to activate a toplevel.
         */
        public signal void ActivationToken (uint32 id, string activation_token);

        /** To be used by the non-standard "inline-reply" capability */
        public signal void NotificationReplied (uint32 id, string text);
    }
}
