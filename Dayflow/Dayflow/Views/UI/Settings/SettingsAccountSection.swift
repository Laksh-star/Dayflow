import AppKit
import SwiftUI

struct SettingsAccountSection: View {
  private let appSupportPath =
    FileManager.default.homeDirectoryForCurrentUser
    .appendingPathComponent("Library/Application Support/DayflowDev")
    .path

  var body: some View {
    VStack(alignment: .leading, spacing: SettingsStyle.sectionSpacing) {
      localForkSection
    }
  }

  private var localForkSection: some View {
    SettingsSection(
      title: "LN's Dayflow Dev",
      subtitle: "This fork runs locally with your own providers, storage, exports, and integrations."
    ) {
      VStack(alignment: .leading, spacing: 18) {
        HStack(alignment: .top, spacing: 14) {
          Image("DayflowLogo")
            .resizable()
            .scaledToFit()
            .frame(width: 38, height: 38)

          VStack(alignment: .leading, spacing: 6) {
            HStack(spacing: 8) {
              Text("Local fork mode")
                .font(.custom("Figtree", size: 18))
                .fontWeight(.bold)
                .foregroundColor(SettingsStyle.text)

              SettingsBadge(text: "DEV", isAccent: true)
            }

            Text(
              "Pro billing, referrals, and hosted-account upgrade flows are hidden in this build so the settings reflect the fork you are actively developing."
            )
            .font(.custom("Figtree", size: 13))
            .foregroundColor(SettingsStyle.secondary)
            .fixedSize(horizontal: false, vertical: true)
          }
        }

        HStack(alignment: .top, spacing: 12) {
          LocalForkInfoTile(label: "App", value: Bundle.main.object(forInfoDictionaryKey: "CFBundleName") as? String ?? "Dayflow Dev")
          LocalForkInfoTile(label: "Bundle ID", value: Bundle.main.bundleIdentifier ?? "teleportlabs.com.Dayflow.dev")
        }

        HStack(alignment: .top, spacing: 12) {
          LocalForkInfoTile(label: "Data folder", value: appSupportPath)
          LocalForkInfoTile(label: "Installed app", value: "/Applications/Dayflow Dev.app")
        }

        VStack(alignment: .leading, spacing: 7) {
          SettingsStatusDot(state: .good, label: "Local storage isolated")
          SettingsStatusDot(state: .good, label: "Provider setup lives under Settings > Providers")
          SettingsStatusDot(state: .good, label: "Exports, Toggl, repair, and project tagging live under Settings > Export")
        }
      }
      .padding(18)
      .background(
        RoundedRectangle(cornerRadius: 10, style: .continuous)
          .fill(Color.white)
      )
      .overlay(
        RoundedRectangle(cornerRadius: 10, style: .continuous)
          .stroke(SettingsStyle.divider, lineWidth: 1)
      )
    }
  }
}

private struct LocalForkInfoTile: View {
  let label: String
  let value: String

  var body: some View {
    VStack(alignment: .leading, spacing: 5) {
      Text(label.uppercased())
        .font(.custom("Figtree", size: 10))
        .fontWeight(.bold)
        .foregroundColor(SettingsStyle.meta)

      Text(value)
        .font(.custom("Figtree", size: 12))
        .fontWeight(.semibold)
        .foregroundColor(SettingsStyle.text)
        .lineLimit(2)
        .truncationMode(.middle)
        .textSelection(.enabled)
    }
    .frame(maxWidth: .infinity, alignment: .leading)
    .padding(12)
    .background(
      RoundedRectangle(cornerRadius: 8, style: .continuous)
        .fill(Color.black.opacity(0.025))
    )
  }
}

private func formattedEntitlementDate(_ value: String?) -> String? {
  guard let value, !value.isEmpty else { return nil }

  if value.count >= 10 {
    let datePrefix = String(value.prefix(10))
    let dateOnlyFormatter = DateFormatter()
    dateOnlyFormatter.locale = Locale(identifier: "en_US_POSIX")
    dateOnlyFormatter.timeZone = TimeZone(secondsFromGMT: 0)
    dateOnlyFormatter.dateFormat = "yyyy-MM-dd"

    if let date = dateOnlyFormatter.date(from: datePrefix) {
      let displayFormatter = DateFormatter()
      displayFormatter.locale = Locale.current
      displayFormatter.timeZone = TimeZone(secondsFromGMT: 0)
      displayFormatter.dateStyle = .medium
      displayFormatter.timeStyle = .none
      return displayFormatter.string(from: date)
    }
  }

  let formatters: [ISO8601DateFormatter] = [
    {
      let formatter = ISO8601DateFormatter()
      formatter.formatOptions = [.withInternetDateTime, .withFractionalSeconds]
      return formatter
    }(),
    {
      let formatter = ISO8601DateFormatter()
      formatter.formatOptions = [.withInternetDateTime]
      return formatter
    }(),
  ]

  let date = formatters.compactMap { $0.date(from: value) }.first
  guard let date else { return nil }

  let displayFormatter = DateFormatter()
  displayFormatter.locale = Locale.current
  displayFormatter.dateStyle = .medium
  displayFormatter.timeStyle = .none
  return displayFormatter.string(from: date)
}

private struct ActiveProCard: View {
  let entitlement: DayflowEntitlement
  let email: String
  let isBusy: Bool
  let signOutAction: () -> Void
  let manageBillingAction: () -> Void

  private var isGifted: Bool {
    entitlement.source == "manual"
  }

  private var title: String {
    isGifted ? "Gifted Pro" : "Dayflow Pro"
  }

  private var badge: String {
    isGifted ? "Gifted" : "Active"
  }

  private var description: String {
    if isGifted {
      return
        "You have complimentary Dayflow Pro access. There is no billing to manage for this account."
    }

    return "Your Pro access is active on this Mac and attached to your Dayflow account."
  }

  private var dateLabel: String {
    if formattedEntitlementDate(entitlement.currentPeriodEnd) == nil {
      return "Status"
    }

    return isGifted ? "Access through" : "Renews"
  }

  private var dateValue: String {
    formattedEntitlementDate(entitlement.currentPeriodEnd) ?? "Active"
  }

  var body: some View {
    VStack(alignment: .leading, spacing: 18) {
      HStack(alignment: .top, spacing: 16) {
        planIcon

        VStack(alignment: .leading, spacing: 5) {
          HStack(alignment: .firstTextBaseline, spacing: 10) {
            Text(title)
              .font(.custom("Figtree", size: 22))
              .fontWeight(.bold)
              .foregroundColor(SettingsStyle.text)

            SettingsBadge(text: badge.uppercased(), isAccent: true)
          }

          Text(description)
            .font(.custom("Figtree", size: 13))
            .foregroundColor(SettingsStyle.secondary)
            .fixedSize(horizontal: false, vertical: true)
        }

        Spacer(minLength: 16)

        SettingsStatusDot(state: .good, label: "Active")
          .padding(.top, 4)
      }

      HStack(alignment: .top, spacing: 12) {
        ActiveProInfoTile(label: "Signed in as", value: email)
        ActiveProInfoTile(label: dateLabel, value: dateValue)
      }

      Rectangle()
        .fill(SettingsStyle.divider)
        .frame(height: 1)

      HStack(alignment: .center, spacing: 16) {
        ProFeatureList()

        Spacer(minLength: 16)

        HStack(spacing: 8) {
          SettingsSecondaryButton(
            title: "Sign out",
            systemImage: "rectangle.portrait.and.arrow.right",
            isDisabled: isBusy,
            action: signOutAction
          )

          if !isGifted {
            SettingsPrimaryButton(
              title: "Manage billing",
              systemImage: "creditcard",
              isLoading: isBusy,
              action: manageBillingAction
            )
          }
        }
      }
    }
    .padding(18)
    .background(
      RoundedRectangle(cornerRadius: 10, style: .continuous)
        .fill(Color.white)
    )
    .overlay(
      RoundedRectangle(cornerRadius: 10, style: .continuous)
        .stroke(SettingsStyle.divider, lineWidth: 1)
    )
  }

  @ViewBuilder
  private var planIcon: some View {
    if isGifted {
      ZStack {
        RoundedRectangle(cornerRadius: 10, style: .continuous)
          .fill(SettingsStyle.ink.opacity(0.1))
        Image(systemName: "gift.fill")
          .font(.system(size: 15, weight: .semibold))
          .foregroundColor(SettingsStyle.ink)
      }
      .frame(width: 34, height: 34)
    } else {
      Image("DayflowLogo")
        .resizable()
        .scaledToFit()
        .frame(width: 34, height: 34)
    }
  }
}

private struct ActiveProInfoTile: View {
  let label: String
  let value: String

  var body: some View {
    VStack(alignment: .leading, spacing: 5) {
      Text(label.uppercased())
        .font(.custom("Figtree", size: 10))
        .fontWeight(.bold)
        .kerning(0.5)
        .foregroundColor(SettingsStyle.meta)

      Text(value)
        .font(.custom("Figtree", size: 14))
        .fontWeight(.semibold)
        .foregroundColor(SettingsStyle.text)
        .lineLimit(1)
        .truncationMode(.middle)
    }
    .frame(maxWidth: .infinity, alignment: .leading)
    .padding(12)
    .background(
      RoundedRectangle(cornerRadius: 8, style: .continuous)
        .fill(Color.white.opacity(0.45))
    )
    .overlay(
      RoundedRectangle(cornerRadius: 8, style: .continuous)
        .stroke(SettingsStyle.divider, lineWidth: 1)
    )
  }
}

private struct ReferralProgramCard: View {
  let summary: DayflowReferralSummary?
  @Binding var inviteEmail: String
  @Binding var applyReferralCode: String
  let copiedReferralLink: Bool
  let isSignedIn: Bool
  let isBusy: Bool
  let copyAction: () -> Void
  let sendInviteAction: () -> Void
  let applyCodeAction: () -> Void
  let signInAction: () -> Void
  let refreshAction: () -> Void

  @State private var selectedTab: ReferralTab = .refer

  private enum ReferralTab: CaseIterable, Hashable {
    case refer
    case past
    case apply
  }

  var body: some View {
    VStack(alignment: .leading, spacing: 23) {
      header

      VStack(alignment: .leading, spacing: 16) {
        tabBar
        contentPanel
      }
    }
    .padding(20)
    .background(
      RoundedRectangle(cornerRadius: 8, style: .continuous)
        .fill(Color.white)
    )
    .task {
      if isSignedIn && summary == nil {
        refreshAction()
      }
    }
  }

  private var header: some View {
    VStack(alignment: .leading, spacing: 12) {
      Text("Refer and earn rewards")
        .font(.custom("Figtree", size: 16))
        .fontWeight(.bold)
        .foregroundColor(Color(hex: "333333"))

      Text("Give a month of Dayflow Pro and earn $20 in credits for each person you refer!")
        .font(.custom("Figtree", size: 12))
        .foregroundColor(Color(hex: "333333"))
    }
    .frame(maxWidth: .infinity, alignment: .leading)
  }

  private var tabBar: some View {
    VStack(alignment: .leading, spacing: 0) {
      HStack(spacing: 24) {
        ForEach(ReferralTab.allCases, id: \.self) { tab in
          Button {
            withAnimation(.easeOut(duration: 0.16)) {
              selectedTab = tab
            }
          } label: {
            Text(tabTitle(for: tab))
              .font(.custom("Figtree", size: 12))
              .fontWeight(selectedTab == tab ? .bold : .regular)
              .foregroundColor(Color(hex: "333333"))
              .padding(.bottom, 8)
              .overlay(alignment: .bottom) {
                if selectedTab == tab {
                  Rectangle()
                    .fill(Color(hex: "333333"))
                    .frame(height: 2)
                }
              }
          }
          .buttonStyle(.plain)
          .pointingHandCursor()
        }

        Spacer()
      }
      .padding(.leading, 8)

      Rectangle()
        .fill(Color(hex: "DFDDDB"))
        .frame(height: 1)
    }
  }

  private var contentPanel: some View {
    VStack(alignment: .center, spacing: 28) {
      switch selectedTab {
      case .refer:
        referPanel
      case .past:
        pastInvitesPanel
      case .apply:
        applyCodePanel
      }
    }
    .padding(20)
    .frame(maxWidth: .infinity)
    .background(
      RoundedRectangle(cornerRadius: 8, style: .continuous)
        .fill(Color(hex: "F5F4F1"))
    )
  }

  private var referPanel: some View {
    VStack(alignment: .center, spacing: 28) {
      ReferralPassCard()

      VStack(alignment: .leading, spacing: 22) {
        howItWorks
        if isSignedIn {
          inviteLinkControl
        } else {
          signInReferralPrompt
        }
      }
      .frame(maxWidth: .infinity, alignment: .leading)
    }
  }

  private var signInReferralPrompt: some View {
    HStack(alignment: .center, spacing: 12) {
      VStack(alignment: .leading, spacing: 4) {
        Text("Sign in to get your invite link")
          .font(.custom("Figtree", size: 12))
          .fontWeight(.bold)
          .foregroundColor(Color(hex: "333333"))

        Text(
          "Referral credits are tied to your Dayflow account so we can credit you when friends join."
        )
        .font(.custom("Figtree", size: 11))
        .foregroundColor(Color(hex: "72706D"))
        .fixedSize(horizontal: false, vertical: true)
      }

      Spacer(minLength: 12)

      ReferralMiniButton(
        title: "Sign in",
        style: .send,
        isDisabled: isBusy,
        action: signInAction
      )
    }
  }

  private var inviteLinkControl: some View {
    VStack(alignment: .leading, spacing: 5) {
      Text("Your invite link")
        .font(.custom("Figtree", size: 12))
        .foregroundColor(Color(hex: "333333"))

      HStack(spacing: 8) {
        ReferralFieldText(
          icon: "link",
          text: summary?.inviteURL ?? "Loading invite link...",
          color: Color(hex: "333333")
        )

        ReferralMiniButton(
          title: copiedReferralLink ? "Copied" : "Copy",
          style: .copy,
          isDisabled: summary == nil,
          action: copyAction
        )
      }
    }
  }

  private var sendInviteControl: some View {
    VStack(alignment: .leading, spacing: 5) {
      Text("Send invites")
        .font(.custom("Figtree", size: 12))
        .foregroundColor(Color(hex: "333333"))

      HStack(spacing: 8) {
        ReferralEmailField(email: $inviteEmail, isDisabled: isBusy)

        ReferralMiniButton(
          title: "Send",
          style: .send,
          isDisabled: isBusy || inviteEmail.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty,
          action: sendInviteAction
        )
      }
    }
  }

  private var howItWorks: some View {
    VStack(alignment: .leading, spacing: 8) {
      Text("How it works")
        .font(.custom("Figtree", size: 12))
        .fontWeight(.bold)
        .foregroundColor(Color(hex: "333333"))

      VStack(alignment: .leading, spacing: 4) {
        ReferralStepRow(
          icon: .system("point.3.connected.trianglepath.dotted"),
          content: Text("Share your invite link")
        )
        ReferralStepRow(
          icon: .menuBarMark,
          content: Text("They sign up and get a ") + Text("free month of Dayflow Pro!").bold()
        )
        ReferralStepRow(
          icon: .system("sparkles"),
          content: Text("You earn ") + Text("1 month of Dayflow Pro (stackable!)").bold()
            + Text(", when they use Dayflow for a week.")
        )
      }
    }
    .frame(width: 332, alignment: .leading)
  }

  private var pastInvitesPanel: some View {
    VStack(alignment: .leading, spacing: 18) {
      if let invites = summary?.invites, !invites.isEmpty {
        VStack(alignment: .leading, spacing: 0) {
          ForEach(invites.prefix(8)) { invite in
            HStack(spacing: 12) {
              VStack(alignment: .leading, spacing: 3) {
                Text(invite.email)
                  .font(.custom("Figtree", size: 12))
                  .fontWeight(.semibold)
                  .foregroundColor(Color(hex: "333333"))
                  .lineLimit(1)
                  .truncationMode(.middle)

                Text(inviteStatusText(invite))
                  .font(.custom("Figtree", size: 11))
                  .foregroundColor(Color(hex: "72706D"))
              }

              Spacer()

              SettingsBadge(
                text: invite.status.uppercased(),
                isAccent: invite.unlockedAt != nil
              )
            }
            .padding(.vertical, 8)

            if invite.id != invites.prefix(8).last?.id {
              Rectangle()
                .fill(Color(hex: "DFDDDB"))
                .frame(height: 1)
            }
          }
        }
      } else {
        EmptyReferralState(text: "No invites yet.")
      }
    }
    .frame(maxWidth: .infinity, alignment: .leading)
  }

  private var applyCodePanel: some View {
    VStack(alignment: .leading, spacing: 18) {
      Text("Redeem a referral code")
        .font(.custom("Figtree", size: 12))
        .fontWeight(.bold)
        .foregroundColor(Color(hex: "333333"))

      HStack(spacing: 8) {
        ReferralCodeField(code: $applyReferralCode, isDisabled: isBusy)

        ReferralMiniButton(
          title: "Apply",
          style: .send,
          isDisabled: isBusy || applyReferralCode.count != 6,
          action: applyCodeAction
        )
      }
    }
    .frame(maxWidth: .infinity, minHeight: 140, alignment: .topLeading)
  }

  private func tabTitle(for tab: ReferralTab) -> String {
    switch tab {
    case .refer:
      return "Refer"
    case .past:
      return "Past referrals (\(summary?.invites.count ?? 0))"
    case .apply:
      return "Apply referral"
    }
  }

  private func inviteStatusText(_ invite: DayflowReferralInvite) -> String {
    if invite.unlockedAt != nil {
      return "Reward earned"
    }
    if invite.claimedAt != nil {
      return "\(String(format: "%.1f", invite.usageHours)) / 40 hours recorded"
    }
    return "Invite sent"
  }
}

private struct BillingPlanCard: View {
  let title: String
  let price: String
  let cadence: String
  let note: String
  let badge: String?
  let isSelected: Bool
  let action: () -> Void

  var body: some View {
    Button(action: action) {
      VStack(alignment: .leading, spacing: 12) {
        HStack(alignment: .firstTextBaseline, spacing: 8) {
          Text(title)
            .font(.custom("Figtree", size: 13))
            .fontWeight(.bold)
            .foregroundColor(SettingsStyle.text)

          Spacer(minLength: 8)

          if let badge {
            SettingsBadge(text: badge.uppercased(), isAccent: true)
          }
        }

        HStack(alignment: .firstTextBaseline, spacing: 4) {
          Text(price)
            .font(.custom("InstrumentSerif-Regular", size: 38))
            .foregroundColor(SettingsStyle.text)
          Text(cadence)
            .font(.custom("Figtree", size: 13))
            .fontWeight(.semibold)
            .foregroundColor(SettingsStyle.secondary)
        }

        Text(note)
          .font(.custom("Figtree", size: 12))
          .foregroundColor(SettingsStyle.secondary)
          .fixedSize(horizontal: false, vertical: true)
      }
      .frame(maxWidth: .infinity, minHeight: 132, alignment: .topLeading)
      .padding(14)
      .background(
        RoundedRectangle(cornerRadius: 8, style: .continuous)
          .fill(isSelected ? SettingsStyle.ink.opacity(0.06) : Color.white.opacity(0.55))
      )
      .overlay(
        RoundedRectangle(cornerRadius: 8, style: .continuous)
          .stroke(isSelected ? SettingsStyle.ink.opacity(0.8) : SettingsStyle.divider, lineWidth: 1)
      )
    }
    .buttonStyle(.plain)
    .pointingHandCursor()
  }
}

private struct ProFeatureList: View {
  private let features = [
    "Zero setup cloud AI for timeline generation",
    "Daily and weekly reports without provider setup",
    "Priority support",
    "Processed securely and never used to train AI models",
  ]

  var body: some View {
    VStack(alignment: .leading, spacing: 8) {
      ForEach(features, id: \.self) { feature in
        HStack(alignment: .top, spacing: 8) {
          Image(systemName: "checkmark.circle.fill")
            .font(.system(size: 12, weight: .semibold))
            .foregroundColor(SettingsStyle.statusGood)
            .padding(.top, 1)

          Text(feature)
            .font(.custom("Figtree", size: 12))
            .foregroundColor(SettingsStyle.text)
            .fixedSize(horizontal: false, vertical: true)
        }
      }
    }
    .padding(.top, 2)
  }
}
