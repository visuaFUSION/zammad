# Copyright (C) 2012-2023 Zammad Foundation, https://zammad-foundation.org/

require 'rails_helper'

RSpec.describe 'Mobile > Ticket > Articles', app: :mobile, authenticated_as: :agent, type: :system do
  let(:group)                { create(:group) }
  let(:agent)                { create(:agent, groups: [group]) }

  context 'when opening ticket with a single article' do
    let(:ticket) { create(:ticket, title: 'Ticket Title', group: group) }
    let!(:article) { create(:ticket_article, body: 'Article 1', ticket: ticket, internal: false) }

    it 'see a single article and no "load more"' do
      visit "/tickets/#{ticket.id}"
      expect(page).to have_text(article.body)
      expect(page).to have_no_text('load')
    end
  end

  context 'when opening ticket with 6 articles page' do
    let(:ticket) { create(:ticket, title: 'Ticket Title', group: group) }
    let!(:articles) do
      (1..6).map do |number|
        create(:ticket_article, body: "Article #{number}", ticket: ticket)
      end
    end

    it 'see all 6 articles' do
      visit "/tickets/#{ticket.id}"

      articles.each do |article|
        expect(page).to have_text(article.body, count: 1)
      end

      expect(page).to have_no_text('load')
    end
  end

  context 'when opening ticket with a lot of articles' do
    let(:ticket) { create(:ticket, title: 'Ticket Title', group: group) }
    let!(:articles) do
      (1..10).map do |number|
        create(:ticket_article, body: "Article #{number}.", ticket: ticket)
      end
    end

    it 'can use "load more" button' do
      visit "/tickets/#{ticket.id}"

      expect(page).to have_text('Article 1.')

      (5..9).each do |number|
        expect(page).to have_text(articles[number].body, count: 1)
      end

      expect(page).to have_no_text('Article 5.')

      click('button', text: 'load 4 more')

      wait_for_gql('apps/mobile/pages/ticket/graphql/queries/ticket/articles.graphql')

      (1..4).each do |number|
        expect(page).to have_text(articles[number].body, count: 1)
      end

      expect(page).to have_no_text('load')
    end
  end

  context 'when retrying security' do
    let(:ticket) do
      # Import S/MIME mail without certificates present.
      Setting.set('smime_integration', true)
      smime_mail = Rails.root.join('spec/fixtures/files/smime/sender_is_signer.eml').read
      allow(ARGF).to receive(:read).and_return(smime_mail)
      Channel::Driver::MailStdin.new
      Ticket.last
    end

    let(:agent) { create(:agent, groups: [ticket.group]) }

    it 'updates state on successful retry' do
      visit "/tickets/#{ticket.id}"

      create(:smime_certificate, :with_private, fixture: 'smime1@example.com')

      find_button('Security Error').click
      find_button('Try again').click

      # visually updates state
      expect(find('[aria-label="Signed"]')).to be_present

      expect(page).to have_text('The signature was successfully verified.')
      expect(page).to have_no_text('Security Error')
    end

    it 'shows error on unsucessful retry' do
      visit "/tickets/#{ticket.id}"

      find_button('Security Error').click
      find_button('Try again').click

      expect(page).to have_text('Certificate for verification could not be found.')
      expect(page).to have_text('Security Error')
      expect(page).to have_no_css('[aria-label="Signed"]')
    end
  end
end
